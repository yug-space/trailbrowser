// trailbrowser.c - Lightweight native Linux browser shell.
//
// GTK draws the native controls; WebKitGTK renders the web page. This avoids
// Electron and keeps the browser shell small while still using a real engine.

#include <ctype.h>
#include <stdio.h>
#include <string.h>

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

#define APP_ID "space.yug.trailbrowser"
#define APP_NAME "TrailBrowser"
#define HOME_URL "https://www.google.com"

typedef struct {
    GtkApplication *application;
    GtkWidget *window;
    GtkWidget *address;
    GtkWidget *back_button;
    GtkWidget *forward_button;
    GtkWidget *reload_button;
    GtkWidget *home_button;
    GtkWidget *progress;
    GtkWidget *status;
    WebKitWebView *web_view;
    gboolean address_dirty;
    gchar *last_recorded_url;
} Browser;

static gchar *home_dir_path(const gchar *filename);
static gchar *state_file_path(void);
static gchar *history_file_path(void);
static void write_browser_state(gboolean running);
static void load_uri(Browser *browser, const gchar *uri);

static gchar *trimmed_copy(const gchar *input) {
    gchar *copy = g_strdup(input ? input : "");
    return g_strstrip(copy);
}

static gboolean has_whitespace(const gchar *input) {
    for (const gchar *p = input; p && *p; p++) {
        if (g_ascii_isspace(*p)) return TRUE;
    }
    return FALSE;
}

static gboolean has_supported_scheme(const gchar *input) {
    gchar *scheme = g_uri_parse_scheme(input);
    if (!scheme) return FALSE;

    gboolean ok = g_ascii_strcasecmp(scheme, "http") == 0 ||
                  g_ascii_strcasecmp(scheme, "https") == 0 ||
                  g_ascii_strcasecmp(scheme, "file") == 0 ||
                  g_ascii_strcasecmp(scheme, "about") == 0;
    g_free(scheme);
    return ok;
}

static gboolean looks_local(const gchar *input) {
    return g_str_has_prefix(input, "localhost") ||
           g_str_has_prefix(input, "127.") ||
           g_str_has_prefix(input, "0.0.0.0") ||
           g_str_has_prefix(input, "::1") ||
           g_str_has_prefix(input, "[");
}

static gboolean looks_like_host_or_local_address(const gchar *input) {
    if (looks_local(input)) return TRUE;

    GRegex *regex = g_regex_new(
        "^(([A-Za-z0-9-]+\\.)+[A-Za-z]{2,}|\\d{1,3}(\\.\\d{1,3}){3})"
        "(:[0-9]{1,5})?([/?#].*)?$",
        0, 0, NULL);
    if (!regex) return FALSE;

    gboolean matched = g_regex_match(regex, input, 0, NULL);
    g_regex_unref(regex);
    return matched;
}

static gchar *search_uri_for_query(const gchar *query) {
    gchar *escaped = g_uri_escape_string(query, NULL, TRUE);
    gchar *uri = g_strdup_printf("https://www.google.com/search?q=%s", escaped);
    g_free(escaped);
    return uri;
}

static gchar *uri_for_input(const gchar *input) {
    gchar *trimmed = trimmed_copy(input);
    if (!trimmed || trimmed[0] == '\0') {
        g_free(trimmed);
        return NULL;
    }

    if (has_whitespace(trimmed)) {
        gchar *uri = search_uri_for_query(trimmed);
        g_free(trimmed);
        return uri;
    }

    if (has_supported_scheme(trimmed) || strstr(trimmed, "://")) {
        return trimmed;
    }

    if (looks_like_host_or_local_address(trimmed)) {
        const gchar *scheme = looks_local(trimmed) ? "http://" : "https://";
        gchar *uri = g_strconcat(scheme, trimmed, NULL);
        g_free(trimmed);
        return uri;
    }

    gchar *uri = search_uri_for_query(trimmed);
    g_free(trimmed);
    return uri;
}

static gboolean is_sensitive_query_name(const gchar *name) {
    static const gchar *markers[] = {
        "token", "secret", "password", "passwd", "pass", "auth",
        "session", "sid", "key", "credential", "code", NULL
    };

    gchar *lower = g_ascii_strdown(name ? name : "", -1);
    gboolean sensitive = FALSE;
    for (guint i = 0; markers[i]; i++) {
        if (strstr(lower, markers[i])) {
            sensitive = TRUE;
            break;
        }
    }
    g_free(lower);
    return sensitive;
}

static gchar *redact_query(const gchar *query) {
    if (!query || query[0] == '\0') return g_strdup("");

    GString *out = g_string_new("");
    gchar **pairs = g_strsplit(query, "&", -1);
    for (guint i = 0; pairs && pairs[i]; i++) {
        if (i > 0) g_string_append_c(out, '&');

        gchar **parts = g_strsplit(pairs[i], "=", 2);
        const gchar *name = parts[0] ? parts[0] : "";
        if (is_sensitive_query_name(name)) {
            g_string_append_printf(out, "%s=%%5Bredacted%%5D", name);
        } else {
            g_string_append(out, pairs[i]);
        }
        g_strfreev(parts);
    }
    g_strfreev(pairs);
    return g_string_free(out, FALSE);
}

static gchar *redacted_uri(const gchar *uri) {
    const gchar *question = strchr(uri, '?');
    if (!question) return g_strdup(uri);

    const gchar *fragment = strchr(question, '#');
    gchar *prefix = g_strndup(uri, (gsize)(question - uri + 1));
    gchar *query = fragment ? g_strndup(question + 1, (gsize)(fragment - question - 1))
                            : g_strdup(question + 1);
    gchar *redacted = redact_query(query);
    gchar *result = fragment ? g_strconcat(prefix, redacted, fragment, NULL)
                             : g_strconcat(prefix, redacted, NULL);
    g_free(prefix);
    g_free(query);
    g_free(redacted);
    return result;
}

static gchar *json_escape(const gchar *value) {
    GString *out = g_string_new("");
    for (const gchar *p = value ? value : ""; *p; p++) {
        switch (*p) {
            case '"': g_string_append(out, "\\\""); break;
            case '\\': g_string_append(out, "\\\\"); break;
            case '\b': g_string_append(out, "\\b"); break;
            case '\f': g_string_append(out, "\\f"); break;
            case '\n': g_string_append(out, "\\n"); break;
            case '\r': g_string_append(out, "\\r"); break;
            case '\t': g_string_append(out, "\\t"); break;
            default:
                if ((unsigned char)*p < 0x20) {
                    g_string_append_printf(out, "\\u%04x", (unsigned char)*p);
                } else {
                    g_string_append_c(out, *p);
                }
                break;
        }
    }
    return g_string_free(out, FALSE);
}

static gchar *host_from_uri(const gchar *uri) {
    const gchar *start = strstr(uri, "://");
    start = start ? start + 3 : uri;
    if (g_str_has_prefix(start, "//")) start += 2;

    const gchar *path = strpbrk(start, "/?#");
    const gchar *end = path ? path : start + strlen(start);

    const gchar *at = memchr(start, '@', (size_t)(end - start));
    if (at) start = at + 1;

    if (*start == '[') {
        const gchar *closing = memchr(start, ']', (size_t)(end - start));
        if (closing) return g_strndup(start + 1, (gsize)(closing - start - 1));
    }

    const gchar *colon = memchr(start, ':', (size_t)(end - start));
    if (colon) end = colon;
    return start < end ? g_strndup(start, (gsize)(end - start)) : g_strdup("");
}

static gchar *iso_timestamp_now(void) {
    GDateTime *now = g_date_time_new_now_local();
    gchar *stamp = g_date_time_format(now, "%Y-%m-%dT%H:%M:%S%z");
    g_date_time_unref(now);
    return stamp;
}

static gchar *support_dir_path(void) {
    gchar *dir = g_build_filename(g_get_user_data_dir(), "trailbrowser", NULL);
    g_mkdir_with_parents(dir, 0700);
    return dir;
}

static gchar *home_dir_path(const gchar *filename) {
    gchar *dir = support_dir_path();
    gchar *path = g_build_filename(dir, filename, NULL);
    g_free(dir);
    return path;
}

static gchar *history_file_path(void) {
    return home_dir_path("history.jsonl");
}

static gchar *state_file_path(void) {
    return home_dir_path("state.json");
}

static void write_browser_state(gboolean running) {
    gchar *path = state_file_path();
    gchar *history_path = history_file_path();
    gchar *stamp = iso_timestamp_now();
    gchar *escaped_history = json_escape(history_path);
    gchar *escaped_stamp = json_escape(stamp);

    gchar *json = g_strdup_printf(
        "{\n"
        "  \"running\": %s,\n"
        "  \"updatedAt\": \"%s\",\n"
        "  \"historyFile\": \"%s\",\n"
        "  \"cookiesExposed\": false\n"
        "}\n",
        running ? "true" : "false",
        escaped_stamp,
        escaped_history);
    g_file_set_contents(path, json, -1, NULL);

    g_free(json);
    g_free(escaped_history);
    g_free(escaped_stamp);
    g_free(stamp);
    g_free(history_path);
    g_free(path);
}

static void append_history_entry(Browser *browser) {
    const gchar *uri = webkit_web_view_get_uri(browser->web_view);
    if (!uri || uri[0] == '\0') return;

    gchar *safe_uri = redacted_uri(uri);
    if (browser->last_recorded_url && g_strcmp0(browser->last_recorded_url, safe_uri) == 0) {
        g_free(safe_uri);
        return;
    }
    g_free(browser->last_recorded_url);
    browser->last_recorded_url = g_strdup(safe_uri);

    const gchar *title = webkit_web_view_get_title(browser->web_view);
    gchar *host = host_from_uri(safe_uri);
    gchar *stamp = iso_timestamp_now();
    gchar *history_path = history_file_path();

    gchar *e_stamp = json_escape(stamp);
    gchar *e_title = json_escape(title);
    gchar *e_uri = json_escape(safe_uri);
    gchar *e_host = json_escape(host);
    gchar *line = g_strdup_printf(
        "{\"timestamp\":\"%s\",\"title\":\"%s\",\"url\":\"%s\","
        "\"host\":\"%s\",\"source\":\"TrailBrowser\"}\n",
        e_stamp, e_title, e_uri, e_host);

    FILE *file = fopen(history_path, "a");
    if (file) {
        fputs(line, file);
        fclose(file);
    }

    g_free(line);
    g_free(e_host);
    g_free(e_uri);
    g_free(e_title);
    g_free(e_stamp);
    g_free(history_path);
    g_free(stamp);
    g_free(host);
    g_free(safe_uri);
}

static void update_navigation_buttons(Browser *browser) {
    gtk_widget_set_sensitive(browser->back_button,
                             webkit_web_view_can_go_back(browser->web_view));
    gtk_widget_set_sensitive(browser->forward_button,
                             webkit_web_view_can_go_forward(browser->web_view));
}

static void update_address_if_not_editing(Browser *browser) {
    if (browser->address_dirty) return;

    const gchar *uri = webkit_web_view_get_uri(browser->web_view);
    if (uri) gtk_entry_set_text(GTK_ENTRY(browser->address), uri);
}

static void load_uri(Browser *browser, const gchar *uri) {
    gtk_entry_set_text(GTK_ENTRY(browser->address), uri);
    browser->address_dirty = FALSE;
    gtk_label_set_text(GTK_LABEL(browser->status), "Loading");
    webkit_web_view_load_uri(browser->web_view, uri);
}

static void load_address_input(Browser *browser) {
    const gchar *text = gtk_entry_get_text(GTK_ENTRY(browser->address));
    gchar *uri = uri_for_input(text);
    if (!uri) return;

    load_uri(browser, uri);
    g_free(uri);
}

static void on_address_activate(GtkEntry *entry, gpointer user_data) {
    (void)entry;
    load_address_input(user_data);
}

static void on_address_changed(GtkEditable *editable, gpointer user_data) {
    (void)editable;
    ((Browser *)user_data)->address_dirty = TRUE;
}

static void on_back_clicked(GtkButton *button, gpointer user_data) {
    (void)button;
    Browser *browser = user_data;
    if (webkit_web_view_can_go_back(browser->web_view)) {
        webkit_web_view_go_back(browser->web_view);
    }
}

static void on_forward_clicked(GtkButton *button, gpointer user_data) {
    (void)button;
    Browser *browser = user_data;
    if (webkit_web_view_can_go_forward(browser->web_view)) {
        webkit_web_view_go_forward(browser->web_view);
    }
}

static void on_reload_clicked(GtkButton *button, gpointer user_data) {
    (void)button;
    Browser *browser = user_data;
    if (webkit_web_view_is_loading(browser->web_view)) {
        webkit_web_view_stop_loading(browser->web_view);
    } else {
        webkit_web_view_reload(browser->web_view);
    }
}

static void on_home_clicked(GtkButton *button, gpointer user_data) {
    (void)button;
    load_uri(user_data, HOME_URL);
}

static void on_load_changed(WebKitWebView *web_view,
                            WebKitLoadEvent load_event,
                            gpointer user_data) {
    Browser *browser = user_data;

    switch (load_event) {
        case WEBKIT_LOAD_STARTED:
            gtk_label_set_text(GTK_LABEL(browser->status), "Loading");
            break;
        case WEBKIT_LOAD_COMMITTED:
            update_address_if_not_editing(browser);
            break;
        case WEBKIT_LOAD_FINISHED:
            gtk_label_set_text(GTK_LABEL(browser->status), "Ready");
            update_address_if_not_editing(browser);
            append_history_entry(browser);
            write_browser_state(TRUE);
            break;
        case WEBKIT_LOAD_REDIRECTED:
            update_address_if_not_editing(browser);
            break;
    }

    update_navigation_buttons(browser);
    (void)web_view;
}

static gboolean on_load_failed(WebKitWebView *web_view,
                               WebKitLoadEvent load_event,
                               gchar *failing_uri,
                               GError *error,
                               gpointer user_data) {
    (void)web_view;
    (void)load_event;
    (void)failing_uri;
    Browser *browser = user_data;
    gtk_label_set_text(GTK_LABEL(browser->status), error ? error->message : "Failed");
    update_navigation_buttons(browser);
    return FALSE;
}

static void on_progress_notify(WebKitWebView *web_view,
                               GParamSpec *pspec,
                               gpointer user_data) {
    (void)pspec;
    Browser *browser = user_data;
    double progress = webkit_web_view_get_estimated_load_progress(web_view);
    gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(browser->progress), progress);
    gtk_widget_set_visible(browser->progress, progress > 0.0 && progress < 1.0);
}

static void on_navigation_state_notify(WebKitWebView *web_view,
                                       GParamSpec *pspec,
                                       gpointer user_data) {
    (void)web_view;
    (void)pspec;
    update_navigation_buttons(user_data);
}

static void on_window_destroy(GtkWidget *widget, gpointer user_data) {
    (void)widget;
    Browser *browser = user_data;
    write_browser_state(FALSE);
    g_free(browser->last_recorded_url);
    g_free(browser);
}

static GtkWidget *icon_button(const gchar *icon_name, const gchar *fallback, const gchar *tooltip) {
    GtkWidget *button = gtk_button_new_from_icon_name(icon_name, GTK_ICON_SIZE_BUTTON);
    if (!button) button = gtk_button_new_with_label(fallback);
    gtk_widget_set_tooltip_text(button, tooltip);
    gtk_widget_set_size_request(button, 36, 32);
    gtk_style_context_add_class(gtk_widget_get_style_context(button), "tb-flat");
    return button;
}

// Near-black + warm-orange theme matching the macOS build, applied as a CSS
// provider over the default screen so it themes every native GTK control.
static void apply_theme(void) {
    GtkSettings *settings = gtk_settings_get_default();
    if (settings) {
        g_object_set(settings, "gtk-application-prefer-dark-theme", TRUE, NULL);
    }

    static const gchar *css =
        "window { background-color: #0a0a0b; color: #f3f3f4; }\n"
        ".tb-toolbar { background-color: #111113; border-bottom: 1px solid rgba(255,255,255,0.08); }\n"
        "entry.tb-address {\n"
        "  background: #1b1b1f; color: #f3f3f4;\n"
        "  border-radius: 9px; border: 1px solid rgba(255,255,255,0.08);\n"
        "  padding: 4px 12px; caret-color: #f76b1c; min-height: 26px;\n"
        "}\n"
        "entry.tb-address:focus { border-color: #f76b1c; }\n"
        "entry.tb-address selection { background: rgba(247,107,28,0.35); }\n"
        "button.tb-flat {\n"
        "  background: transparent; color: #8a8a90;\n"
        "  border: none; box-shadow: none; border-radius: 7px;\n"
        "}\n"
        "button.tb-flat:hover { background: rgba(255,255,255,0.08); color: #f3f3f4; }\n"
        "button.tb-flat:active { background: rgba(255,255,255,0.16); }\n"
        "label.tb-status { color: #8a8a90; }\n"
        "progressbar.tb-progress trough { background: transparent; border: none; min-height: 2px; }\n"
        "progressbar.tb-progress progress { background: #f76b1c; border: none; min-height: 2px; }\n";

    GtkCssProvider *provider = gtk_css_provider_new();
    gtk_css_provider_load_from_data(provider, css, -1, NULL);
    gtk_style_context_add_provider_for_screen(
        gdk_screen_get_default(),
        GTK_STYLE_PROVIDER(provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(provider);
}

static void activate(GtkApplication *application, gpointer user_data) {
    (void)user_data;

    apply_theme();

    Browser *browser = g_new0(Browser, 1);
    browser->application = application;

    browser->window = gtk_application_window_new(application);
    gtk_window_set_title(GTK_WINDOW(browser->window), APP_NAME);
    gtk_window_set_default_size(GTK_WINDOW(browser->window), 1200, 760);

    GtkWidget *root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(browser->window), root);

    GtkWidget *toolbar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_style_context_add_class(gtk_widget_get_style_context(toolbar), "tb-toolbar");
    gtk_widget_set_margin_start(toolbar, 8);
    gtk_widget_set_margin_end(toolbar, 8);
    gtk_widget_set_margin_top(toolbar, 8);
    gtk_widget_set_margin_bottom(toolbar, 8);
    gtk_box_pack_start(GTK_BOX(root), toolbar, FALSE, FALSE, 0);

    browser->back_button = icon_button("go-previous-symbolic", "<", "Back");
    browser->forward_button = icon_button("go-next-symbolic", ">", "Forward");
    browser->reload_button = icon_button("view-refresh-symbolic", "R", "Reload");
    browser->home_button = icon_button("go-home-symbolic", "H", "Home");
    browser->address = gtk_entry_new();
    browser->status = gtk_label_new("Ready");
    browser->progress = gtk_progress_bar_new();
    browser->web_view = WEBKIT_WEB_VIEW(webkit_web_view_new());

    gtk_entry_set_placeholder_text(GTK_ENTRY(browser->address), "Search or enter website name");
    gtk_style_context_add_class(gtk_widget_get_style_context(browser->address), "tb-address");
    gtk_style_context_add_class(gtk_widget_get_style_context(browser->status), "tb-status");
    gtk_style_context_add_class(gtk_widget_get_style_context(browser->progress), "tb-progress");
    gtk_box_pack_start(GTK_BOX(toolbar), browser->back_button, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(toolbar), browser->forward_button, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(toolbar), browser->reload_button, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(toolbar), browser->home_button, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(toolbar), browser->address, TRUE, TRUE, 4);
    gtk_box_pack_start(GTK_BOX(toolbar), browser->status, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(root), browser->progress, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(root), GTK_WIDGET(browser->web_view), TRUE, TRUE, 0);
    gtk_widget_set_no_show_all(browser->progress, TRUE);
    gtk_widget_set_visible(browser->progress, FALSE);

    WebKitSettings *settings = webkit_web_view_get_settings(browser->web_view);
    webkit_settings_set_enable_developer_extras(settings, FALSE);

    g_signal_connect(browser->address, "activate", G_CALLBACK(on_address_activate), browser);
    g_signal_connect(browser->address, "changed", G_CALLBACK(on_address_changed), browser);
    g_signal_connect(browser->back_button, "clicked", G_CALLBACK(on_back_clicked), browser);
    g_signal_connect(browser->forward_button, "clicked", G_CALLBACK(on_forward_clicked), browser);
    g_signal_connect(browser->reload_button, "clicked", G_CALLBACK(on_reload_clicked), browser);
    g_signal_connect(browser->home_button, "clicked", G_CALLBACK(on_home_clicked), browser);
    g_signal_connect(browser->web_view, "load-changed", G_CALLBACK(on_load_changed), browser);
    g_signal_connect(browser->web_view, "load-failed", G_CALLBACK(on_load_failed), browser);
    g_signal_connect(browser->web_view, "notify::estimated-load-progress",
                     G_CALLBACK(on_progress_notify), browser);
    g_signal_connect(browser->web_view, "notify::can-go-back",
                     G_CALLBACK(on_navigation_state_notify), browser);
    g_signal_connect(browser->web_view, "notify::can-go-forward",
                     G_CALLBACK(on_navigation_state_notify), browser);
    g_signal_connect(browser->window, "destroy", G_CALLBACK(on_window_destroy), browser);

    update_navigation_buttons(browser);
    write_browser_state(TRUE);
    load_uri(browser, HOME_URL);
    gtk_widget_show_all(browser->window);
    gtk_widget_set_visible(browser->progress, FALSE);
    gtk_widget_grab_focus(browser->address);
}

int main(int argc, char **argv) {
    GtkApplication *application = gtk_application_new(
        APP_ID,
#if GLIB_CHECK_VERSION(2, 74, 0)
        G_APPLICATION_DEFAULT_FLAGS
#else
        G_APPLICATION_FLAGS_NONE
#endif
    );
    g_signal_connect(application, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(application), argc, argv);
    g_object_unref(application);
    return status;
}

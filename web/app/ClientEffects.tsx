"use client";

import { useEffect } from "react";

// Wires progressive effects against the server-rendered marketing page once
// hydration completes.
export default function ClientEffects() {
  useEffect(() => {
    const reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)"
    ).matches;
    const cleanups: Array<() => void> = [];

    // ── Nav: shadow on scroll + mobile menu ──────────────────────
    const nav = document.getElementById("nav");
    if (nav) {
      const onScroll = () =>
        nav.classList.toggle("scrolled", window.scrollY > 12);
      onScroll();
      window.addEventListener("scroll", onScroll, { passive: true });
      cleanups.push(() => window.removeEventListener("scroll", onScroll));

      const toggle = document.getElementById("navToggle");
      const onToggle = () => nav.classList.toggle("menu-open");
      toggle?.addEventListener("click", onToggle);
      cleanups.push(() => toggle?.removeEventListener("click", onToggle));

      const closeMenu = () => nav.classList.remove("menu-open");
      const links = nav.querySelectorAll<HTMLAnchorElement>(".nav-links a");
      links.forEach((a) => a.addEventListener("click", closeMenu));
      cleanups.push(() =>
        links.forEach((a) => a.removeEventListener("click", closeMenu))
      );
    }

    // ── Reveal on scroll ─────────────────────────────────────────
    const revealTargets = document.querySelectorAll<HTMLElement>(
      ".section-head, .feature-card, .chat-card, .bench, .open-grid a, .shortcut, .build-card"
    );
    revealTargets.forEach((el, i) => {
      el.classList.add("reveal");
      el.style.transitionDelay = `${Math.min((i % 6) * 50, 250)}ms`;
    });
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => {
          if (e.isIntersecting) {
            e.target.classList.add("in");
            io.unobserve(e.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
    );
    revealTargets.forEach((el) => io.observe(el));
    cleanups.push(() => io.disconnect());

    // ── Benchmark bars: animate width when in view ───────────────
    const bench = document.querySelector<HTMLElement>(".bench");
    if (bench) {
      const bio = new IntersectionObserver(
        (entries) => {
          entries.forEach((e) => {
            if (!e.isIntersecting) return;
            bench
              .querySelectorAll<HTMLElement>(".bench-fill")
              .forEach((f, i) => {
                setTimeout(() => {
                  f.style.width = (f.dataset.w ?? "0") + "%";
                }, 120 * i);
              });
            bio.disconnect();
          });
        },
        { threshold: 0.4 }
      );
      bio.observe(bench);
      cleanups.push(() => bio.disconnect());
    }

    // ── Chat mock: reveal AI answer after the typing dots ────────
    const chat = document.querySelector<HTMLElement>(".chat");
    if (chat) {
      const cio = new IntersectionObserver(
        (entries) => {
          entries.forEach((e) => {
            if (!e.isIntersecting) return;
            setTimeout(() => chat.classList.add("revealed"), 1400);
            cio.disconnect();
          });
        },
        { threshold: 0.5 }
      );
      cio.observe(chat);
      cleanups.push(() => cio.disconnect());
    }

    // ── Address-bar typing loop in the hero mockup ───────────────
    const typed = document.getElementById("typed");
    const url = typed?.previousElementSibling as HTMLElement | null;
    if (typed && url && !reduceMotion) {
      const phrases = [
        "best trails near big sur",
        "summarize this page",
        "github.com/trailbrowser",
        "wkwebview memory usage",
      ];
      let cancelled = false;
      const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
      (async () => {
        let p = 0;
        while (!cancelled) {
          const word = phrases[p % phrases.length];
          url.style.display = "none";
          for (let i = 0; i <= word.length && !cancelled; i++) {
            typed.textContent = word.slice(0, i);
            await wait(55);
          }
          await wait(1600);
          for (let i = word.length; i >= 0 && !cancelled; i--) {
            typed.textContent = word.slice(0, i);
            await wait(28);
          }
          url.style.display = "";
          await wait(900);
          p++;
        }
      })();
      cleanups.push(() => {
        cancelled = true;
      });
    }

    return () => cleanups.forEach((fn) => fn());
  }, []);

  return null;
}

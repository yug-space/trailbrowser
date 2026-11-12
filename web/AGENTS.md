# Website Agent Notes

This directory is the TrailBrowser public website.

- Framework: Next.js App Router
- Deploy target: Vercel
- Main files: `app/page.tsx`, `app/globals.css`, `app/ClientEffects.tsx`
- Public assets: `public/assets/`

Before editing Next-specific APIs, check the current Next.js docs. This project
uses Next 16, where conventions can differ from older App Router examples.

Verification:

```sh
npm run lint
npm run build
npm audit --audit-level=moderate
```

Keep the site white, sleek, product-focused, and easy to scan. Do not commit
`.next/`, `node_modules/`, screenshots, or generated build output.

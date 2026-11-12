# TrailBrowser Website

This is the public marketing site for TrailBrowser. It is a small Next.js App
Router app intended for Vercel deployment.

## Develop

```sh
npm install
npm run dev
```

Open `http://localhost:3000`.

## Build

```sh
npm run build
```

## Deploy on Vercel

Use `web/` as the project root in Vercel.

- Framework preset: Next.js
- Build command: `npm run build`
- Install command: `npm install`
- Output directory: Next.js default

The site is static-first and uses only local public assets under
`web/public/assets`.

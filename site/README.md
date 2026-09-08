# hnd-viewer — project website

Static single-page website for **hnd-viewer**, the free, open viewer for the
HND-NE3 ear camera.

This is a plain static site: hand-written HTML + CSS, no build step, no
framework, and **no external CDN dependencies**. It loads fine from `file://`
or from any static file server, and it works fully offline.

## Design

Quiet and minimal. Near-white background (`#fafafa`), near-black text
(`#16181d`), hairline separators (`#e5e5e5`), and system fonts only:
serif headings (Georgia / Iowan Old Style / Times New Roman) over a system
sans body. No gradients, no glows, no shadows, no decorative icons; links are
plain near-black underlined text.

## Structure

```
site/
├── index.html        # single-page site (all sections, anchor-linked)
├── css/style.css     # all styling — light, minimal, editorial theme
├── favicon.svg       # site icon (monochrome mark)
├── .nojekyll         # tells GitHub Pages not to run Jekyll
└── README.md         # this file
```

There is deliberately no JavaScript: everything on the page (anchors, smooth
scrolling, layout) works in plain HTML/CSS.

The page is one document with anchor sections: hero → live view (screenshot
placeholder) → what it does → how it works (protocol) → downloads → getting
started → license → footer.

## Preview locally

The site is fully self-contained, so any static server works. From the repo
root:

```sh
python3 -m http.server 8000 -d site
# open http://localhost:8000
```

or from inside `site/`:

```sh
cd site
python3 -m http.server 8000
# open http://localhost:8000
```

You can also just open `site/index.html` directly in a browser — there are no
fetch/XHR dependencies, so the `file://` URL renders identically.

## Deploying to GitHub Pages

The site is deployed from the **`site/` directory** via the GitHub Actions
workflow at `.github/workflows/pages.yml` (repo root). It:

1. Trigger on push to the default branch (and/or new release tags).
2. Check out the repository.
3. Publish the **`site/` directory** as the Pages artifact — e.g. with
   `actions/upload-pages-artifact` using `path: site`, or by pushing `site/`
   to the `gh-pages` branch via a tool like
   `peaceiris/actions-gh-pages` with `publish_dir: site` / `JamesIves/
   github-pages-deploy-action` with `folder: site`.
4. Enable Pages in the repo settings (Settings → Pages → Source: "GitHub
   Actions").

Why this works with no extra steps:

- The site is already static and self-contained — the workflow just publishes
  files, it does not build anything.
- `site/.nojekyll` is already present, so GitHub Pages skips Jekyll and
  serves the raw HTML/CSS.
- Every in-site link is **relative**, so the page works whether Pages serves
  it at the repo root (`https://<owner>.github.io/hnd-viewer/`) or under any
  other base path.

## GitHub links

The page links to the canonical repository at
`https://github.com/fuho/hnd-viewer` (repo, releases, README, and
`docs/PROTOCOL.md`). The repo README and `docs/PROTOCOL.md` links are absolute
GitHub URLs rather than relative links because the Pages deployment publishes
**only** this `site/` directory, so `../README.md` or `docs/PROTOCOL.md`
relative targets would not exist on the deployed site.

### Screenshots

No screenshots exist yet. `index.html` contains a plain light placeholder box
(`.shot-box`) with the muted text "Screenshot coming soon." and an HTML
comment marking exactly where a real screenshot or looping GIF (and its
`<img>`/`<video>` markup) should be dropped in.

# Support website

`website/public/` contains the maintained support and privacy pages and shared assets.
`website/` also holds their browser tests.
Japanese uses `/`, English uses `/en/`, Simplified Chinese uses `/zh-Hans/`, and Traditional Chinese uses `/zh-Hant/`.
Each language has a home page, `/support/`, and `/privacy/`.

Run `mise x -- just check-website` from the repository root.
The command checks types, HTML, CSS, localization, the palette, and browser interactions.
The browser tests use a separate headless Chrome instance and cover navigation, keyboard access, text enlargement, contrast preferences, and failed asset requests.

Run `mise x -- just preview` from `website/` to serve the local preview at `http://127.0.0.1:4173/`.
The [website workflow](../.github/workflows/website.yml) checks and preserves a candidate, verifies its provenance in a protected publication job, and deploys the candidate to `gymemo.yasunobu.dev`.
The candidate includes a CycloneDX inventory of the static assets and a checksum of the preserved archive.
After publication, `mise x -- just check-public-website` runs the same browser scenarios at the public HTTPS domain.
The [credential workflow](../.github/workflows/credentials.yml) checks authentication without publishing and verifies that an unprotected job can't fetch the website's credentials.
`mise x -- just setup-delivery WORKPLACE` plans the narrowly scoped Doppler identity setup.
Adding `--apply` creates the matching account and identity, refuses conflicting existing permissions, and verifies the GitHub environment variable.
The [hosting decision](adr/serve-support-pages-from-the-app-repository.md) separates website publication from app distribution.

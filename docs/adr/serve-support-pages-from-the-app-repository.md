---
date: 2026-11-11
---

# Serve support pages from the app repository

## Status

Proposed.

## Context

App Store review needs public support and privacy URLs that describe the shipped app.
The owner chose `gymemo.yasunobu.dev` and requested that the app repository hold the website's source.
The domain is an active Cloudflare zone.

## Decision

Keep the pages, assets, browser tests, and deployment configuration in `website/`.
Publish that directory independently through [Cloudflare Workers static assets](https://developers.cloudflare.com/workers/static-assets/).
Bind `gymemo.yasunobu.dev` as a [Custom Domain](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/), which manages Domain Name System (DNS) records and certificates.
The app remains offline.

## Alternatives

Sites provides managed publication and custom domains, but its publishing workflow also saves source to its own Git repository.
A mirror could keep the app repository authoritative, but adds synchronization.
Direct publication uses the existing Cloudflare account.

## Consequences

Website changes and app changes share review history, but neither publication releases the other.
The repository must pin and check the deployment tool and preserve a separate website check command.
Hosting access remains outside the repository.

## Confirmation

Require the website checks and a deployment dry run before publication, then verify the public localized URLs over HTTPS.
Reconsider if the site needs server behavior or the owner changes hosting providers.

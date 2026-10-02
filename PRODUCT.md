# Product

## Register

product

## Users and purpose

OpenStrap is a local-first Flutter companion for wearable owners reviewing sleep,
recovery and activity, recording habits, and managing their own data. Measurement,
storage and analytics stay on the phone. The interface must make measured values,
estimates, missing inputs and stale readings distinguishable.

## Approved direction

The owner selected Strata (variant C in design/redesign-directions.html) in T3
session 97e2110f-e746-450c-83ad-5fd7d58e1f2e and requested continuation. Dark-only,
mineral colours, terrain contours and restrained instrument typography are the
existing direction. Do not restart the design selection or revive earlier designs.

## Design principles

- One metric, one meaning and one colour; avoid duplicate readings.
- Terrain encodes actual data. Decorative terrain never implies a measurement.
- Keep familiar navigation, editing, source attribution and privacy controls.
- Use the shared Strata system throughout, with layouts fitted to each task.
- Preserve missing-data explanations, source dates and confidence.

## Accessibility and inclusion

Preserve large-text layouts through 3.1x, 44-point targets, screen-reader labels,
reduced-motion behaviour, translated copy and contrast checks. Do not hide a
reading or its units to make a layout fit.

## Anti-references

Generic neon fitness dashboards, mascot cards, decorative glass, arbitrary scores,
and a cosmetic reskin that leaves important populated states unreviewed.

## Visual system

The detailed source of truth is lib/ui2/README.md and its theme.dart tokens.

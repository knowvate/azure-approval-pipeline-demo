# CLAUDE.md

This repo is a reference implementation of a safe, approval-gated GitHub
Actions pipeline that deploys Development → UAT → Production with
Terraform, where all three environments share one Azure subscription.

Read `docs/BRIEF.md` first. It lists the goal, the safety properties that
must be kept, what to check before adapting the pattern to another repo,
and lessons from running it for real.

Key files:
- `.github/workflows/pipeline.yml`: the whole pipeline as one graph
  (lint, test, Terraform validate, Checkov, build, then the environments).
- `.github/workflows/deploy-environment.yml`: Plan (read-only identity)
  and then Deploy (gated GitHub environment, applies the saved plan,
  deploys the prebuilt artifact, smoke-tests).
- `bootstrap/main.tf`: resource groups, per-environment identities,
  OIDC federated credentials, custom read-only planner role, role
  assignments and per-environment state. Applied once, locally, by an Owner.
- `infra/`: what the pipeline deploys (App Service F1 per environment).

The Azure side is currently torn down. Repo variables point at deleted
identities, so a push to `main` that touches code will fail at
Development / Plan until `bootstrap/` is re-applied and the variables are
updated.

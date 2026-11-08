# Prompt for Claude at work

Paste this into Claude to start applying the pattern to another repo:

> Read https://github.com/knowvate/azure-approval-pipeline-demo — start with `docs/BRIEF.md`, then `.github/workflows/pipeline.yml`, `.github/workflows/deploy-environment.yml` and `bootstrap/main.tf`. I want this pattern applied to our repo. Our dev/UAT/prod are all in one subscription (work-mainsub), distinguished by an `Environment` tag (Development/UAT/Production). Before writing anything, go through the "Things that will differ at work" section against our setup and tell me what's missing.

If GitHub isn't reachable from work, clone the repo or paste `docs/BRIEF.md`
and those three files into the conversation instead.

A 2-minute walkthrough of the pipeline running for real, with real GitHub
and Azure screenshots, is in [approval-pipeline.mp4](approval-pipeline.mp4).

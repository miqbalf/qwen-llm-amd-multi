---
name: agent-model-assignments
description: Which models to use for each agent role in this project
metadata:
  type: user
---

# Agent Model Assignments

When dispatching subagents for this project, use these model assignments:

| Role | Model |
|------|-------|
| Writer (code, scripts, docs) | DeepSeek Flash |
| Unit test author | DeepSeek Flash |
| Reviewer (code review, verification) | DeepSeek Pro |
| Planner (design, architecture) | DeepSeek Pro |
| Final check / gate | DeepSeek Pro |

**Why:** DeepSeek Flash is fast and cheap for generating code and tests.
DeepSeek Pro is more thorough for review, planning, and final verification
where correctness matters more than speed.

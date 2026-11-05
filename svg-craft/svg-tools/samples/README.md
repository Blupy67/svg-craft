# samples

This folder is empty on purpose. It is an optional place for your own reference SVGs.

If you want Claude to match an existing style, put those SVGs here, or in a subfolder such as `samples\my-art\`. Then point `-Compare` at one of them:

```powershell
pwsh -File "$HOME\.claude\svg-tools\render-svg.ps1" -Path <new files> -Compare "$HOME\.claude\svg-tools\samples\my-art\logo.svg" -Sizes 24,96 -Out <scratchpad>\compare.png
```

The tools and the self-test don't need anything here. `selftest.ps1` creates its own test files in a temporary folder and deletes them afterward.

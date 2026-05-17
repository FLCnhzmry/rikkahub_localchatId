# Patches

Store `git format-patch` output files here.

Recommended flow:

```powershell
git commit -m "add local chat header injection"
pwsh ./scripts/export-patches.ps1 -BaseRef upstream/2.1.8
```

The automation workflow applies every `*.patch` file in this folder to the selected upstream release tag with `git am --3way`.

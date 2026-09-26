# Pause a tool call for approval

Return this from a `can_use_tool` callback (see
[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md))
to stop the run before the tool executes and save the pending call to
disk. Approve or deny it later, possibly from another R process, with
`agent$resume_approval()`;
[`approval_read()`](https://jameshwade.github.io/deputy/reference/approval_read.md)
shows what is waiting.

## Usage

``` r
PermissionResultPending(reason = "Approval required")
```

## Arguments

- reason:

  Why the call needs approval, as one non-empty string.

## Value

A `PermissionResultPending` object.

## Details

The agent needs an `approval_dir`, and the tool must be registered with
`convert = FALSE`, so its function receives the raw JSON arguments. Tool
results should be strings, JSON from
[`jsonlite::toJSON()`](https://jeroen.r-universe.dev/jsonlite/reference/fromJSON.html),
or ellmer content objects. Inputs or results shaped like a list with
`version`, `class` and `props` fields are rejected, because ellmer would
read them back as serialized objects.

## See also

[`vignette("approvals")`](https://jameshwade.github.io/deputy/articles/approvals.md),
[`approval_read()`](https://jameshwade.github.io/deputy/reference/approval_read.md),
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md)

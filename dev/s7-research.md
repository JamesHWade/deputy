# S7 research for issue #59

Research date: 2026-09-06. Baseline: Deputy `9e9aa93149a227348c35cd9f1b0a5bcb44e45ad5`.
This note separates upstream API facts from recommendations; the ADR records
the integrated spike results.

## Recommendation

Adopt S7 for Deputy value objects, as explicitly selected after reviewing the
spike, while retaining R6 for mutable runtime objects. Use Deputy-owned S7
classes with typed, validated properties and compose ellmer values where they
belong in the payload. The benefit is a consistent value model and explicit
contracts; stored-property immutability still needs a deliberate implementation.
The ellmer inheritance assessment below explains why these are separate domain
classes. This supersedes the initial recommendation to retain the S3 event.

At the baseline, `AgentEvent()` was already an S3 list and S7 was already in
`Imports`; the migration therefore changes an existing value representation
rather than replacing an R6 event. `HookMatcher` carries a callback closure,
so its configuration can be read-only while captured callback state remains
mutable. [Baseline event implementation](https://github.com/JamesHWade/deputy/blob/9e9aa93149a227348c35cd9f1b0a5bcb44e45ad5/R/agent-result.R),
[baseline matcher](https://github.com/JamesHWade/deputy/blob/9e9aa93149a227348c35cd9f1b0a5bcb44e45ad5/R/hooks.R),
[baseline metadata](https://github.com/JamesHWade/deputy/blob/9e9aa93149a227348c35cd9f1b0a5bcb44e45ad5/DESCRIPTION)

## Read-only properties do not imply immutable stored records

`new_property()` in released S7 0.2.2 accepts `class`, `getter`, `setter`,
`validator`, `default`, and `name`; there is no `readonly` argument. A getter
without a setter creates a read-only computed property. That property is
excluded from the default constructor, and S7 does not automatically validate
the getter's return type. Supplying storage and validating it becomes the
class author's responsibility. [S7 property reference](https://rconsortium.github.io/S7/reference/new_property.html)

The official frozen-property example uses a custom setter to reject changes
after initialization. Thus a stored HookMatcher field can be frozen, but its
guard becomes a setter rather than disappearing. A NULL-based initialization
test also needs care for legitimately nullable fields such as `pattern`:
NULL must not serve as both an allowed initialized value and the uninitialized
sentinel. This is a design implication of the documented pattern.
[S7 classes, frozen properties](https://rconsortium.github.io/S7/articles/classes-objects.html#frozen-properties)

S7 validates stored property types, optional property validators, and class
validators during construction and ordinary property assignment. Cross-field
checks still require a class validator; callback signatures and regex validity
remain domain checks. Low-level attribute assignment can bypass this path,
so S7 read-only properties are an API contract, not an execution sandbox.
[S7 validation](https://rconsortium.github.io/S7/articles/classes-objects.html#validation)

## Value copying and executable state

R6 instances have reference semantics. Its default `clone(deep = TRUE)` copies
direct R6 fields, but does not recursively copy arbitrary environments or
reference objects nested inside lists. This already requires deliberate
ownership boundaries in Deputy. [R6 introduction and cloning](https://r6.r-lib.org/articles/Introduction.html#deep-cloning)

S7 values containing ordinary lists can be copied independently through normal
R replacement operations. Embedded environments remain references; closures
retain their environments. Switching the outer class does not freeze callback
behavior or arbitrary event payloads. R's definition distinguishes closures,
environments, and ordinary data objects. [R language definition](https://stat.ethz.ch/R-manual/R-devel/doc/manual/R-lang.html#Objects)

This minimal probe was run with R 4.6.1 and S7 0.2.2:

```r
library(S7)
Box <- new_class("Box", properties = list(value = class_list))
x <- Box(list(a = 1))
y <- x
y@value$a <- 2
stopifnot(x@value$a == 1, y@value$a == 2)

state <- new.env()
state$a <- 1
x <- Box(list(state = state))
y <- x
y@value$state$a <- 2
stopifnot(x@value$state$a == 2, y@value$state$a == 2)
```

For HookMatcher, evaluate whether changing a local copy is allowed and whether
the registry must retain its original configuration. Neither requirement means
that a host callback's captured counter or service client should be cloned.
For AgentEvent, preserve useful provider content and original conditions;
turning everything into plain immutable data would be a separate payload
contract change. [Current hook and event contracts](../R/hooks.R),
[event payloads](../R/agent-result.R)

## Package integration and version floor

The tested release is [S7 0.2.2](https://github.com/RConsortium/S7/releases/tag/v0.2.2).
Its package metadata declares R >= 3.5.0 and imports `utils`. This does not
raise Deputy's declared R >= 4.1.0 floor. This is a dependency-metadata
conclusion, not evidence that the full Deputy dependency set passes on R 4.1.
[CRAN S7 metadata](https://cran.univ-lyon1.fr/CRAN/web/packages/S7/index.html)

Before R 4.3, package code must use `S7::prop()` or conditionally import S7's
`@` operator. Exported S7 classes need `package = "deputy"`; their S3 class
name becomes `deputy::ClassName`, which affects existing `inherits()` calls
and S3 method names. Class and generic definitions must precede their methods.
[S7 package guide](https://rconsortium.github.io/S7/articles/packages.html)

The online S7 package guide currently describes development version
0.2.2.9000 and recommends `S7_on_load()`, `S7_on_unload()`, and `S7_on_build()`.
Those are **not exported by tested release 0.2.2**. Its bundled
`doc/packages.Rmd` instead prescribes `S7::methods_register()` in `.onLoad()`.
The current roxygen2 guide independently documents that registration API.
Use the released API for this spike. Reproduce the version distinction with:

```r
packageVersion("S7")
packageDescription("S7")[c("Depends", "Imports")]
grep("S7_on_|methods_register", getNamespaceExports("S7"), value = TRUE)
cat(readLines(system.file("doc/packages.Rmd", package = "S7")), sep = "\n")
```

Roxygen2 8.1.0 documents S7 constructors using ordinary `@param` and `@returns`,
with `@prop` for additional properties. Methods registered via `method<-` use
runtime registration and do not need `@export`. Deputy already selects
roxygen2 8.1.0 in DESCRIPTION. [Roxygen2 S7 guide](https://roxygen2.r-lib.org/articles/rd-S7.html),
[Deputy metadata](../DESCRIPTION)

## Compatibility of the selected S7 migration

S7 can extend a list using `parent = class_list`, preserving a list-shaped
payload, or use declared properties with an explicit `$` compatibility method.
These are different designs: the former does not automatically impose a
schema on every list element; the latter needs deliberate handling of existing
`$`, `[[`, `names()`, open-ended fields, and event subclasses. S7's own
compatibility guide demonstrates both approaches.
[S7 list compatibility](https://rconsortium.github.io/S7/articles/compatibility.html#list-classes)

The selected S7 migration must explicitly choose which read interfaces remain
supported while adding meaningful validation. ADR-0009 retains flat `$` reads,
exposes the payload property, and removes whole-event list indexing and S3
subtype tags in favor of the event type property. For HookMatcher, retain
construction validation and registry behavior while documenting the S7
constructor and matching API. Compare the complete supported interfaces,
including compatibility adapters, rather than counting only class-definition
lines. [Event API](../R/agent-result.R), [matcher API](../R/hooks.R)

## Applying the decision to the requested follow-ups

| Type | Current behavior | Evidence required before a migration |
| --- | --- | --- |
| AgentResult | R6 container with public result fields, convenience methods, and a separately protected run context | Show whether value copying simplifies actual result ownership; preserve result helpers and nested provider content; establish the mutability contract explicitly. |
| Permissions | Read-only configuration plus executable policy evaluation and a host callback | Preserve authority narrowing, canonical grants, fail-closed decisions, callback semantics, and construction validation; setter count alone does not justify changing the authority object. |

These follow-up criteria come from the current
[AgentResult implementation](../R/agent-result.R),
[Permissions implementation](../R/permissions.R), and the
[issue follow-up](https://github.com/JamesHWade/deputy/issues/59#issuecomment-5382441309).
They support a separate bounded decision after the HookMatcher/AgentEvent
spike, rather than a migration of every class based on the words "value object".


## Installed-package experiment

A separate disposable package was documented, built, installed into its own
library, and loaded by a fresh `Rscript` process. It passed exported class
identity by class tags, computed-property access, read-only rejection,
`print()` dispatch registered through `.onLoad()`/`methods_register()`, and
RDS round-trip property access and printing. Roxygen generated constructor
arguments and an “Additional properties” section for `@prop`; NAMESPACE
contained `export(Probe)` without a print-method export directive.

The actual tools were R 4.6.1, S7 0.2.2, and **roxygen2 8.0.0**, whereas
Deputy's configured roxygen version is 8.1.0. This demonstrates the tested
integration without claiming verification on 8.1.0 or R 4.1. The first probe
also established that `identical(S7::S7_class(readRDS(...)), Probe)` is not a
valid round-trip expectation: constructor objects were not identical, while
`S7::S7_inherits()` and registered dispatch succeeded.

The initial in-process HookMatcher/AgentEvent spike used `package = NULL`, so it
did not test installed namespaced classes or registration. The mini package
below covers those mechanics. The shipped migration uses `package = "deputy"`
and tests serialized values after loading Deputy in a fresh process; its full
suite and installed-package checks cover the real runtime. The mini-package
experiment itself did not change production R files.

Save the following as an R script and run `Rscript <script>`. It creates only
a disposable package and library under `/private/tmp`; successful execution
prints `PASS`. Its generated source, Rd, NAMESPACE, tarball, and installation
remain in the printed `PROBE_ROOT` for inspection.

```r
root <- tempfile("deputy-s7-package-", tmpdir = "/private/tmp")
dir.create(root)
pkg <- file.path(root, "deputys7probe")
dir.create(file.path(pkg, "R"), recursive = TRUE)
writeLines(c(
  "Package: deputys7probe", "Title: Probe S7 Package Registration",
  "Version: 0.0.0.9000", "Authors@R: person('Test', 'Maintainer', email = 'test@example.org', role = c('aut', 'cre'))",
  "Description: A disposable package for testing S7 documentation and registration.",
  "License: MIT", "Encoding: UTF-8", "Imports: S7", "Roxygen: list(markdown = TRUE)"
), file.path(pkg, "DESCRIPTION"))
writeLines(c(
  "#' A probe value", "#' @param label A character label.",
  "#' @prop width Computed character count, read-only.",
  "#' @returns An S7 Probe value.", "#' @export",
  "Probe <- S7::new_class('Probe', package = 'deputys7probe', properties = list(",
  "  label = S7::class_character,",
  "  width = S7::new_property(S7::class_integer, getter = function(self) nchar(S7::prop(self, 'label')))",
  "))",
  "S7::method(print, Probe) <- function(x, ...) {",
  "  cat('<Probe> ', S7::prop(x, 'label'), '\\n', sep = '')",
  "  invisible(x)", "}"
), file.path(pkg, "R", "probe.R"))
writeLines(".onLoad <- function(...) S7::methods_register()", file.path(pkg, "R", "zzz.R"))
roxygen2::roxygenise(pkg)
rd <- readLines(file.path(pkg, "man", "Probe.Rd"))
stopifnot(any(grepl('width', rd, fixed = TRUE)), any(grepl('label', rd, fixed = TRUE)))
old <- setwd(root)
on.exit(setwd(old), add = TRUE)
stopifnot(system2(file.path(R.home('bin'), 'R'), c('CMD', 'build', shQuote(pkg), '--no-build-vignettes', '--no-manual')) == 0L)
lib <- file.path(root, 'library')
dir.create(lib)
stopifnot(system2(file.path(R.home('bin'), 'R'), c('CMD', 'INSTALL', paste0('--library=', shQuote(lib)), shQuote(file.path(root, 'deputys7probe_0.0.0.9000.tar.gz')))) == 0L)
check <- file.path(root, 'verify.R')
writeLines(c(
  sprintf('.libPaths(c(%s, .libPaths()))', deparse(lib)),
  "library(deputys7probe)", "x <- Probe('hello')",
  "stopifnot(identical(class(x), c('deputys7probe::Probe', 'S7_object')))",
  "stopifnot(identical(S7::prop(x, 'width'), 5L))",
  "stopifnot(identical(capture.output(print(x)), '<Probe> hello'))",
  "stopifnot(inherits(tryCatch({S7::prop(x, 'width') <- 9L; NULL}, error = identity), 'error'))",
  "f <- tempfile(fileext = '.rds'); saveRDS(x, f); y <- readRDS(f)",
  "stopifnot(S7::S7_inherits(y, Probe), identical(S7::prop(y, 'label'), 'hello'))",
  "stopifnot(identical(capture.output(print(y)), '<Probe> hello'))",
  "cat('PASS: installed package class identity, computed property, read-only rejection, registered print, RDS round trip\\n')"
), check)
stopifnot(system2(file.path(R.home('bin'), 'Rscript'), shQuote(check)) == 0L)
cat('PROBE_ROOT=', root, '\n', sep = '')
cat('ROXYGEN=', as.character(packageVersion('roxygen2')), '\n', sep = '')
cat('S7=', as.character(packageVersion('S7')), '\n', sep = '')
cat('RD\n'); cat(rd, sep = '\n')
cat('\nNAMESPACE\n'); cat(readLines(file.path(pkg, 'NAMESPACE')), sep = '\n')
```


## Should Deputy inherit from ellmer?

Use composition for HookMatcher, AgentEvent, AgentResult, and Permissions.
This is a domain recommendation supported by the hierarchy in **released
ellmer 0.5.0**, inspected from `/private/tmp/deputy-cran-library`. Some online
reference pages still identify themselves as 0.4.2; the installed 0.5.0
namespace and constructors were checked for the facts below.

| Deputy value | Closest ellmer class | Relationship |
| --- | --- | --- |
| AgentEvent | Content or Turn | A lifecycle event may contain provider content or a conversation turn. Start, stop, permission, and compaction events are not messages to or from a chatbot. Keep the original ellmer value in its payload. |
| HookMatcher | ToolDef | A matcher holds host callback configuration and selection rules. ToolDef is an executable function advertised to the model, with argument schema, conversion, and annotations. Store a callback function; do not inherit ToolDef. |
| AgentResult | Turn, AssistantTurn, or Round | A governed run result aggregates conversation turns, events, accounting, and stop state. It is not one assistant message or one conversation round. Store the original turns and explicit aggregate metadata. |
| Permissions | ToolDef annotations | A policy evaluates and limits authority across tools. Tool annotations describe a tool and can inform that evaluation; they are not an authority policy superclass. |

`Content` is ellmer's base for provider message content such as text, images,
tool requests, and tool results. Its extension documentation is intended for
new kinds of such content. Subclassing it would assert that every Deputy event
is admissible wherever provider content is expected; that would misrepresent
lifecycle evidence. [ellmer Content contract](https://ellmer.tidyverse.org/reference/Content.html)

`Turn` holds a list of Content values, with user, system, and assistant
specializations. A single chat call can produce several turns because of tool
calling. Thus a run result is broader than one Turn, but broader aggregation
is containment rather than subtype substitutability.
[ellmer Turn contract](https://ellmer.tidyverse.org/reference/Turn.html)

The installed `Round` class also offers no general result base: it has `input`
and `response` lists, a computed `complete` property, and a validator requiring
at least one input turn and excluding tool-result turns from that input. Both
`Content` and `Turn` report `abstract = FALSE`; neither is a generic record
abstraction. The namespace inventory contains no S7 `Event`, `Callback`,
`Permissions`, or general record class. These are local observations of the
released package, reproducible with the code below.

`ToolDef` extends `S7::class_function`, and `tool()` creates the function and
its model-facing schema. Inheriting it would give HookMatcher the wrong
callability and registration contract. Permissions should consume its
annotations through policy checks, preserving their meaning as descriptive
hints. [ellmer tool contract](https://ellmer.tidyverse.org/reference/tool.html)

ellmer's `Chat` is R6 and exposes callback registration methods; in 0.5.0 these
accept functions managed by an internal R6 `CallbackManager`. There is no S7
callback specification to extend. Integrate at `on_tool_request()`,
`on_tool_result()`, `on_request_start()`, and `on_request_end()` using adapter
functions, while Deputy owns event matching and governance.
[ellmer Chat callback interface](https://ellmer.tidyverse.org/reference/Chat.html)

Inheritance would be justified for a future Deputy type only if it truly is
an ellmer content/turn/tool specialization and can satisfy that base's full
consumer contract, including serialization and provider conversion methods.
For the current types, share S7 as the object system and preserve typed ellmer
objects through composition. An S7 property declared as `class_list` checks
the outer list only; homogeneous `turns` or `contents` fields need explicit
per-element `S7::S7_inherits()` validation where that is the actual public
contract. Open-ended event payloads should not be forced into Content types.
[S7 property validation](https://rconsortium.github.io/S7/reference/new_property.html),
[Deputy event payload contract](../R/agent-result.R)

Reproduce the hierarchy observations against the selected release:

```r
.libPaths(c("/private/tmp/deputy-cran-library", .libPaths()))
stopifnot(packageVersion("ellmer") == "0.5.0")
ns <- asNamespace("ellmer")
classes <- Filter(function(n) inherits(get(n, ns), "S7_class"),
  ls(ns, all.names = TRUE))
print(classes)
for (name in c("Content", "Turn", "ToolDef", "Round")) {
  cls <- get(name, ns)
  print(cls)
  print(S7::prop(cls, "abstract"))
  print(S7::prop(cls, "constructor"))
}
print(S7::prop(ellmer::Round, "validator"))
print(get("CallbackManager", ns))
print(ellmer::Chat$public_methods$on_request_start)
```

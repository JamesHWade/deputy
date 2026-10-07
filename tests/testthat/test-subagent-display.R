skip_if_not_installed("xml2")
skip_if_not_installed("htmltools")

test_that("display HTML keeps structure and drops active content", {
  html <- paste0(
    "<div class=\"measure\" onclick=\"steal()\" data-row=\"1\">",
    "<script>steal()</script><strong>60</strong>",
    "<img src=\"data:image/png;base64,iVBORw0KGgo=\" alt=\"plot\" onerror=\"x()\">",
    "<img src=\"javascript:alert(1)\">",
    "<img src=\"https://t.example/p.gif\">",
    "<a href=\"javascript:alert(1)\">bad</a>",
    "<a href=\"https://example.org/doc\">doc</a>",
    "<iframe src=\"https://example.org\"></iframe>",
    "<form action=\"/x\"><input name=\"y\"></form>",
    "<span style=\"color:red;position:fixed;background:url(https://t.example/p.gif)\">r</span>",
    "</div>"
  )
  safe <- subagent_display_html(html)
  expect_identical(
    safe,
    paste0(
      "<div class=\"measure\" data-row=\"1\"><strong>60</strong>",
      "<img src=\"data:image/png;base64,iVBORw0KGgo=\" alt=\"plot\"/>",
      "<img/><img/><a>bad</a>",
      "<a href=\"https://example.org/doc\" target=\"_blank\" ",
      "rel=\"noopener noreferrer\">doc</a>",
      "<span style=\"color:red\">r</span></div>"
    )
  )
})

test_that("inline SVG icons keep their geometry", {
  icon <- paste0(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" ",
    "fill=\"currentColor\" class=\"bi\" viewBox=\"0 0 16 16\">",
    "<path d=\"M1 1h2\"/><path d=\"M4 4h2\"/>",
    "<use href=\"#other\"/><foreignObject><div>x</div></foreignObject>",
    "<animate attributeName=\"x\" to=\"1\"/></svg>"
  )
  expect_identical(
    subagent_display_html(icon),
    paste0(
      "<svg width=\"16\" height=\"16\" fill=\"currentColor\" class=\"bi\" ",
      "viewbox=\"0 0 16 16\"><path d=\"M1 1h2\"></path>",
      "<path d=\"M4 4h2\"></path></svg>"
    )
  )
})

test_that("styles stay scoped to the display's own prefixed ids", {
  html <- paste0(
    "<div id=\"tbl\"><style>",
    "#tbl td{color:red;background:url(https://t.example/p.gif)}",
    "#tbl th, #tbl td{padding:1px}",
    "body{display:none}",
    "#tbl ~ div{display:none}",
    "#other td{color:blue}",
    "@font-face{font-family:x;src:url(https://t.example/f.woff)}",
    "@media (max-width:600px){#tbl td{font-size:10px}body{margin:0}}",
    "</style><table><tr><td id=\"cell\">1</td></tr></table></div>",
    "<div id=\"chat\">spoof</div>"
  )
  safe <- subagent_display_html(html)
  prefix <- regmatches(safe, regexpr("deputy-display-[0-9a-f]{12}-", safe))
  expect_length(prefix, 1L)
  expect_match(
    safe,
    paste0(
      "<style>#",
      prefix,
      "tbl td{color:red}",
      "#",
      prefix,
      "tbl th,#",
      prefix,
      "tbl td{padding:1px}",
      "@media (max-width:600px){#",
      prefix,
      "tbl td{font-size:10px}}",
      "</style>"
    ),
    fixed = TRUE
  )
  expect_match(safe, paste0("<div id=\"", prefix, "tbl\">"), fixed = TRUE)
  expect_match(
    safe,
    paste0("<td id=\"", prefix, "cell\">1</td>"),
    fixed = TRUE
  )
  expect_match(
    safe,
    paste0("<div id=\"", prefix, "chat\">spoof</div>"),
    fixed = TRUE
  )
  expect_no_match(safe, "body|https://t.example|~|blue")
  # Another display with the same ids gets its own prefix.
  other <- subagent_display_html(html)
  expect_false(grepl(prefix, other, fixed = TRUE))
  expect_identical(
    subagent_display_html("<style>#x td{color:red}</style><p>no id</p>"),
    "<p>no id</p>"
  )
})

test_that("nested CSS rules can't escape a declaration", {
  nested <- paste0(
    "<div id=\"a\" style=\"color:red;a:b{} &{position:fixed;inset:0}\">",
    "<style>#a{a:b{} &{position:fixed;inset:0;z-index:99999} ",
    "& ~ *{display:none}}#a td{color:blue}</style>x</div>"
  )
  safe <- subagent_display_html(nested)
  expect_no_match(safe, "[{}].*position|fixed|display:none|~|&")
  expect_match(safe, "style=\"color:red\"", fixed = TRUE)
  expect_match(safe, "td{color:blue}", fixed = TRUE)
})

test_that("malformed and non-HTML input degrades to text or nothing", {
  expect_identical(subagent_display_html(""), "")
  expect_identical(subagent_display_html(NA_character_), "")
  expect_identical(subagent_display_html(c("a", "b")), "")
  expect_identical(
    subagent_display_html("a &nbsp;<b>b</b> <unknown-tag>c</unknown-tag>"),
    "a  <b>b</b> c"
  )
  expect_identical(
    subagent_display_html("<p>1 &lt; 2 &amp; <i>3</i></p>"),
    "<p>1 &lt; 2 &amp; <i>3</i></p>"
  )
})

test_that("only raw HTML display fields are rebuilt", {
  display <- list(
    title = "<b onmouseover=\"x()\">Ran</b>",
    icon = "<script>x()</script>",
    html = "<div>ok</div>",
    footer = "<small>note</small>",
    markdown = "<script>left to the markdown renderer</script>",
    label = "<i>label</i>",
    show_request = FALSE
  )
  safe <- subagent_safe_display(display)
  expect_identical(safe$title, "<b>Ran</b>")
  expect_null(safe$icon)
  expect_identical(safe$html, "<div>ok</div>")
  expect_identical(safe$footer, "<small>note</small>")
  expect_identical(safe$markdown, display$markdown)
  expect_identical(safe$label, display$label)
  expect_false(safe$show_request)
})

test_that("the child panel renders retained displays inertly", {
  skip_if_not_installed("shinychat", "0.5.0")
  request <- ellmer::ContentToolRequest("call_1", "call_measure", list())
  result <- ellmer::ContentToolResult(
    value = "60",
    request = request,
    extra = list(
      display = list(
        title = "Ran a trusted calculation",
        html = "<div onclick=\"x()\"><strong>60</strong></div>"
      )
    )
  )
  safe <- subagent_chat_safe_content(result)
  expect_identical(safe@extra$display$html, "<div><strong>60</strong></div>")
  messages <- subagent_chat_messages(list(
    ellmer::AssistantTurn(list(request)),
    ellmer::UserTurn(list(result))
  ))
  expect_length(messages, 1L)
  rendered <- paste(
    vapply(
      messages[[1L]]$content,
      function(block) paste(unlist(block), collapse = " "),
      character(1)
    ),
    collapse = " "
  )
  expect_match(rendered, "<div><strong>60</strong></div>", fixed = TRUE)
  expect_no_match(rendered, "onclick", fixed = TRUE)
})

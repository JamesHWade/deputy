# Web tools for deputy agents

#' Fetch web page content
#'
#' @description
#' A tool that fetches the content of a web page and returns it as text
#' or markdown. Requires the httr2 package for HTTP requests.
#'
#' For JavaScript-rendered pages, consider using the chromote package
#' with a custom tool implementation.
#'
#' @format A tool definition created with `ellmer::tool()`.
#'
#' @param url The URL of the web page to fetch (tool argument)
#'
#' @details
#' This tool uses httr2 to fetch web content and extracts text from HTML.
#' If the rvest package is available, it extracts the main content more
#' intelligently. If pandoc is available via rmarkdown, HTML is converted
#' to markdown.
#'
#' The tool respects a 30-second timeout and follows redirects.
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = list(tool_web_fetch),
#'   permissions = Permissions$new(web = TRUE)
#' )
#' }
#'
#' @seealso [tools_web()]
#' @export
tool_web_fetch <- ellmer::tool(
  fun = function(url) {
    if (!rlang::is_installed("httr2")) {
      return(ellmer::tool_reject(
        "Cannot fetch web content: package 'httr2' is required. Install with install.packages('httr2')"
      ))
    }

    tryCatch(
      {
        # Fetch the page
        resp <- httr2::request(url) |>
          httr2::req_timeout(30) |>
          httr2::req_user_agent("deputy R package (https://github.com/JamesHWade/deputy)") |>
          httr2::req_perform()

        content_type <- httr2::resp_content_type(resp)
        body <- httr2::resp_body_string(resp)

        # If it's not HTML, return the raw content (truncated if large)
        if (!grepl("text/html", content_type, ignore.case = TRUE)) {
          if (nchar(body) > 50000) {
            body <- paste0(substr(body, 1, 50000), "\n... [truncated]")
          }
          return(paste0(
            "URL: ", url, "\n",
            "Content-Type: ", content_type, "\n\n",
            body
          ))
        }

        # Extract and clean HTML content
        content <- extract_web_content(body, url)

        paste0(
          "<web_page url=\"", url, "\">\n",
          content,
          "\n</web_page>"
        )
      },
      error = function(e) {
        ellmer::tool_reject(paste("Error fetching URL:", e$message))
      }
    )
  },
  name = "web_fetch",
  description = "Fetch the content of a web page and return it as text. Use this to read articles, documentation, or other web content.",
  arguments = list(
    url = ellmer::type_string("The URL of the web page to fetch (must start with http:// or https://)")
  ),

  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    destructive_hint = FALSE,
    open_world_hint = TRUE
  )
)

#' Search the web
#'
#' @description
#' A tool that performs a web search and returns results. Uses DuckDuckGo's
#' HTML search results by default.
#'
#' @format A tool definition created with `ellmer::tool()`.
#'
#' @param query The search query (tool argument)
#' @param num_results Maximum number of results to return (tool argument)
#'
#' @details
#' This tool searches the web using DuckDuckGo and returns a list of results
#' with titles, URLs, and snippets. For more sophisticated search needs,
#' consider using a dedicated search API.
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = list(tool_web_search),
#'   permissions = Permissions$new(web = TRUE)
#' )
#' }
#'
#' @seealso [tools_web()]
#' @export
tool_web_search <- ellmer::tool(
  fun = function(query, num_results = 10) {
    if (!rlang::is_installed("httr2")) {
      return(ellmer::tool_reject(
        "Cannot perform web search: package 'httr2' is required. Install with install.packages('httr2')"
      ))
    }

    tryCatch(
      {
        # Use DuckDuckGo HTML search
        search_url <- paste0(
          "https://html.duckduckgo.com/html/?q=",
          utils::URLencode(query, reserved = TRUE)
        )

        resp <- httr2::request(search_url) |>
          httr2::req_timeout(30) |>
          httr2::req_user_agent("deputy R package (https://github.com/JamesHWade/deputy)") |>
          httr2::req_perform()

        body <- httr2::resp_body_string(resp)

        # Parse search results
        results <- parse_duckduckgo_results(body, num_results)

        if (length(results) == 0) {
          return(paste0("No results found for query: ", query))
        }

        # Format results
        formatted <- vapply(seq_along(results), function(i) {
          r <- results[[i]]
          paste0(
            i, ". ", r$title, "\n",
            "   URL: ", r$url, "\n",
            "   ", r$snippet
          )
        }, character(1))

        paste0(
          "Search results for: ", query, "\n\n",
          paste(formatted, collapse = "\n\n")
        )
      },
      error = function(e) {
        ellmer::tool_reject(paste("Error performing search:", e$message))
      }
    )
  },
  name = "web_search",
  description = "Search the web for information. Returns a list of relevant web pages with titles, URLs, and snippets.",
  arguments = list(
    query = ellmer::type_string("The search query"),
    num_results = ellmer::type_integer(
      "Maximum number of results to return. Default is 10.",
      required = FALSE
    )
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    destructive_hint = FALSE,
    open_world_hint = TRUE
  )
)

# Internal helper functions ------------------------------------------------

#' Extract main content from HTML
#'
#' @param html HTML string
#' @param url Original URL (for resolving relative links)
#' @return Extracted text content
#' @noRd
extract_web_content <- function(html, url) {
  # Try rvest for better HTML parsing

if (rlang::is_installed("rvest") && rlang::is_installed("xml2")) {
    tryCatch(
      {
        doc <- xml2::read_html(html)

        # Remove script, style, and other unwanted elements
        xml2::xml_remove(xml2::xml_find_all(doc, "//script"))
        xml2::xml_remove(xml2::xml_find_all(doc, "//style"))
        xml2::xml_remove(xml2::xml_find_all(doc, "//noscript"))
        xml2::xml_remove(xml2::xml_find_all(doc, "//nav"))
        xml2::xml_remove(xml2::xml_find_all(doc, "//footer"))
        xml2::xml_remove(xml2::xml_find_all(doc, "//header"))

        # Try to find main content
        main_content <- xml2::xml_find_first(doc, "//main | //article | //*[@role='main'] | //*[@id='content'] | //*[@class='content']")

        if (is.na(main_content)) {
          main_content <- xml2::xml_find_first(doc, "//body")
        }

        if (is.na(main_content)) {
          # Fallback to simple text extraction
          return(simple_html_to_text(html))
        }

        # Convert to markdown if pandoc available
        if (has_pandoc()) {
          inner_html <- as.character(main_content)
          return(html_to_markdown(inner_html))
        }

        # Otherwise extract text
        text <- xml2::xml_text(main_content)
        clean_text(text)
      },
      error = function(e) {
        simple_html_to_text(html)
      }
    )
  } else {
    simple_html_to_text(html)
  }
}

#' Simple HTML to text conversion
#'
#' @param html HTML string
#' @return Plain text
#' @noRd
simple_html_to_text <- function(html) {
  # Remove script and style content
  html <- gsub("<script[^>]*>.*?</script>", "", html, ignore.case = TRUE, perl = TRUE)
  html <- gsub("<style[^>]*>.*?</style>", "", html, ignore.case = TRUE, perl = TRUE)

  # Remove HTML tags
  text <- gsub("<[^>]+>", " ", html)

  # Decode common HTML entities
  text <- gsub("&nbsp;", " ", text)
  text <- gsub("&amp;", "&", text)
  text <- gsub("&lt;", "<", text)
  text <- gsub("&gt;", ">", text)
  text <- gsub("&quot;", "\"", text)
  text <- gsub("&#39;", "'", text)

  clean_text(text)
}

#' Clean extracted text
#'
#' @param text Text to clean
#' @return Cleaned text
#' @noRd
clean_text <- function(text) {
  # Collapse multiple whitespace
  text <- gsub("\\s+", " ", text)

  # Collapse multiple newlines
  text <- gsub("\n{3,}", "\n\n", text)

  # Trim
  text <- trimws(text)

  # Truncate if too long
  if (nchar(text) > 50000) {
    text <- paste0(substr(text, 1, 50000), "\n... [truncated]")
  }

  text
}

#' Check if pandoc is available
#'
#' @return Logical
#' @noRd
has_pandoc <- function() {
  if (!rlang::is_installed("rmarkdown")) {
    return(FALSE)
  }
  tryCatch(
    {
      rmarkdown::pandoc_available()
    },
    error = function(e) FALSE
  )
}

#' Convert HTML to markdown using pandoc
#'
#' @param html HTML string
#' @return Markdown string
#' @noRd
html_to_markdown <- function(html) {
  if (!has_pandoc()) {
    return(simple_html_to_text(html))
  }

  tryCatch(
    {
      # Write HTML to temp file
      tmp_in <- withr::local_tempfile(fileext = ".html")
      writeLines(html, tmp_in)

      # Convert with pandoc
      tmp_out <- withr::local_tempfile(fileext = ".md")

      rmarkdown::pandoc_convert(
        input = tmp_in,
        to = "markdown_strict-raw_html",
        output = tmp_out,
        options = c("--wrap=none")
      )

      md <- paste(readLines(tmp_out, warn = FALSE), collapse = "\n")
      clean_text(md)
    },
    error = function(e) {
      simple_html_to_text(html)
    }
  )
}

#' Parse DuckDuckGo search results
#'
#' @param html HTML response from DuckDuckGo
#' @param max_results Maximum results to return
#' @return List of search result lists with title, url, snippet
#' @noRd
parse_duckduckgo_results <- function(html, max_results = 10) {
  results <- list()

  if (rlang::is_installed("rvest") && rlang::is_installed("xml2")) {
    tryCatch(
      {
        doc <- xml2::read_html(html)

        # Find result containers
        result_nodes <- xml2::xml_find_all(doc, "//div[contains(@class, 'result')]")

        for (i in seq_len(min(length(result_nodes), max_results))) {
          node <- result_nodes[[i]]

          # Extract title and URL
          title_node <- xml2::xml_find_first(node, ".//a[contains(@class, 'result__a')]")
          snippet_node <- xml2::xml_find_first(node, ".//a[contains(@class, 'result__snippet')]")

          if (!is.na(title_node)) {
            title <- xml2::xml_text(title_node)
            url <- xml2::xml_attr(title_node, "href")

            # DuckDuckGo uses redirect URLs, try to extract actual URL
            if (grepl("uddg=", url)) {
              url_match <- regmatches(url, regexpr("uddg=([^&]+)", url))
              if (length(url_match) > 0) {
                url <- utils::URLdecode(sub("uddg=", "", url_match))
              }
            }

            snippet <- if (!is.na(snippet_node)) xml2::xml_text(snippet_node) else ""

            results[[length(results) + 1]] <- list(
              title = trimws(title),
              url = url,
              snippet = trimws(snippet)
            )
          }
        }
      },
      error = function(e) {
        # Return empty results on parse error
        list()
      }
    )
  } else {
    # Fallback: simple regex parsing
    # Extract links with class result__a
    pattern <- '<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>([^<]+)</a>'
    matches <- gregexpr(pattern, html, perl = TRUE)
    matched <- regmatches(html, matches)[[1]]

    for (i in seq_len(min(length(matched), max_results))) {
      url_match <- regmatches(matched[i], regexpr('href="([^"]+)"', matched[i]))
      title_match <- regmatches(matched[i], regexpr('>([^<]+)</a>', matched[i]))

      if (length(url_match) > 0 && length(title_match) > 0) {
        url <- gsub('href="|"', "", url_match)
        title <- gsub('>|</a>', "", title_match)

        results[[length(results) + 1]] <- list(
          title = trimws(title),
          url = url,
          snippet = ""
        )
      }
    }
  }

  results
}

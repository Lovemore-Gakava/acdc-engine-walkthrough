# The walkthrough as an app: change a decision, and CDISC's engine runs again.
#
# Locally:    shiny::runApp()          (from this folder)
# In a browser, with no R installed: the published Shinylive page (see README),
# where the same code and the same engine run in the browser through webR.

library(shiny)
library(jsonlite)
library(nanoparquet)
library(car)
library(emmeans)

source(file.path("R", "setup.R"))
source(file.path("R", "steps.R"))
adlb_file <- as.data.frame(nanoparquet::read_parquet(adlb_path))
SUBJECT <- "CTX-NSCLC-301-SITE001-0092"

setting <- function(id, label, choices, where) {
  div(class = "setting",
      radioButtons(id, label, choices = choices, selected = DEFAULT_SETTINGS[[id]]),
      div(class = "where", where))
}

card <- function(n, title, what, ...) {
  div(class = "card", h3(paste0("Step ", n, ": ", title)), p(class = "what", what), ...)
}

ui <- fluidPage(
  tags$head(tags$style(HTML("
    body { font-family: system-ui, sans-serif; max-width: 1280px; margin: auto; color: #1f2328; }
    h1 { font-size: 1.6em; margin: 18px 0 4px; }
    .lede { color: #555; margin-bottom: 14px; max-width: 900px; }
    .setting { border-bottom: 1px solid #e5e5e5; padding-bottom: 6px; margin-bottom: 10px; }
    .where { font-size: 0.82em; color: #6a6a6a; margin-top: -6px; }
    .card { border: 1px solid #d8dee4; border-radius: 8px; padding: 12px 16px; margin-bottom: 12px; }
    .card h3 { font-size: 1.05em; margin: 0 0 4px; }
    .what { color: #555; font-size: 0.92em; margin-bottom: 8px; }
    .result { border: 2px solid #0969da; border-radius: 8px; padding: 12px 16px; margin-bottom: 14px; }
    .result.failed { border-color: #cf222e; }
    .big { font-size: 1.5em; font-weight: 600; }
    .pair { display: flex; gap: 40px; flex-wrap: wrap; }
    .label { font-size: 0.85em; color: #6a6a6a; }
    .err { color: #cf222e; font-weight: 600; }
    .skip { color: #8c959f; font-style: italic; }
    pre { background: #f6f8fa; border: none; font-size: 0.85em; }
    table { font-size: 0.9em; }
  "))),
  h1("CDISC's AC/DC engine, step by step"),
  div(class = "lede",
      "ALT change from baseline at a visit, TORIVA-LUNG 301, ANCOVA with baseline as covariate. ",
      "Change a decision on the left and the engine runs again, here, on all of TORIVA's ADLB. ",
      "The settings are the decisions behind the number; under each is where it is recorded today. ",
      a("About this", href = "https://github.com/Lovemore-Gakava/acdc-engine-walkthrough", target = "_blank")),
  sidebarLayout(
    sidebarPanel(width = 4,
      setting("order", "Which baseline record the engine finds first",
              c("ADLB as TORIVA ships it" = "file", "ADLB sorted latest date first" = "latest"),
              "Not a setting anywhere: the engine keeps the first record in the baseline window, so file order decides."),
      setting("covariate", "Covariate",
              c("ADaM's BASE" = "BASE", "The app's default" = "default"),
              "Typed on the app's last screen (step 8); saved nowhere."),
      setting("population", "Population",
              c("SAFFL = Y" = "SAFFL", "ITTFL = Y" = "ITTFL", "As in the saved chain: SAF" = "saved"),
              "Typed at step 8; the saved chain holds 'SAF'. In TORIVA's ADLB every ALT record is in both populations."),
      setting("visit", "Analysis visit",
              c("Cycle 2 Day 1" = "C2D1", "Cycle 3 Day 1" = "C3D1", "Cycle 4 Day 1" = "C4D1",
                "Cycle 5 Day 1" = "C5D1", "Cycle 6 Day 1" = "C6D1"),
              "In the saved chain."),
      setting("treatment", "Treatment filter",
              c("None: keep both arms" = "none", "As in the saved chain: 'Torivumab vs Placebo'" = "saved"),
              "Typed at step 8; the saved chain holds a comparison label."),
      actionButton("reset", "Back to the captured run")
    ),
    mainPanel(width = 8,
      uiOutput("result"),
      card(0, "the decisions in the inputs",
           "The slices pick records: 'endpoint' the records analysed, 'parameter_baseline' the baseline records.",
           verbatimTextOutput("step0")),
      card(1, "read TORIVA's ADLB", "The laboratory analysis dataset, at the pinned commit.",
           verbatimTextOutput("step1")),
      card("2-3", "ingest and derive",
           paste("ADaM variables are renamed to concepts, then the change from baseline is derived:",
                 "each value minus the baseline value. Where a subject has more than one record in the",
                 "baseline window, the engine keeps the first. One subject:"),
           tableOutput("step3")),
      card(4, "bind", "Which column plays which role in the model.", tableOutput("step4")),
      card(5, "slice", "The endpoint slice's filters, in turn.", uiOutput("step5")),
      card(6, "fit", "The model the engine runs, and its comparison of the arms.",
           uiOutput("step6"), tableOutput("step6table")),
      card(7, "check the two baselines",
           "The response uses the engine's baseline; the covariate uses the column chosen above.",
           uiOutput("step7"))
    )
  )
)

server <- function(input, output, session) {
  settings <- reactive(list(order = input$order, covariate = input$covariate,
                            population = input$population, visit = input$visit,
                            treatment = input$treatment))
  adlb <- reactive(order_adlb(adlb_file, input$order))
  derived <- reactive(derive_concepts(adlb()))          # once per order
  run <- reactive(engine_steps(adlb(), settings(), derived = derived()))
  ref <- reactive(toriva_reference(adlb_file, settings()))

  observeEvent(input$reset, for (id in names(DEFAULT_SETTINGS))
    updateRadioButtons(session, id, selected = DEFAULT_SETTINGS[[id]]))

  failed_at <- function(steps) {
    r <- run()
    if (!is.null(r$failed) && r$failed %in% steps) div(class = "err", "Failed here: ", r$error)
  }
  not_reached <- function(after) {
    r <- run(); order <- c("derive", "bind", "slice", "fit")
    !is.null(r$failed) && match(r$failed, order) < match(after, order)
  }

  output$result <- renderUI({
    r <- run(); rf <- ref()
    if (!is.null(r$failed)) {
      return(div(class = "result failed", div(class = "big", "No result"),
                 p("The engine stopped at the ", strong(r$failed), " step: ", r$error)))
    }
    ct <- r$contrast
    div(class = "result",
        div(class = "pair",
            div(div(class = "label", "The engine (placebo minus torivumab)"),
                div(class = "big", sprintf("%.3f", ct$estimate)),
                sprintf("SE %.3f, 95%% CI %.2f to %.2f", ct$SE, ct$CI_lower, ct$CI_upper)),
            div(div(class = "label", "TORIVA's ADaM, same model, same visit"),
                div(class = "big", sprintf("%.3f", rf$estimate)),
                sprintf("SE %.3f, n %d", rf$SE, rf$n)),
            div(div(class = "label", "Subjects whose two baselines differ"),
                div(class = "big", sprintf("%d of %d", r$n_differ, r$n_both)))))
  })

  output$step0 <- renderText({
    r <- run(); lines <- character(0)
    for (s in r$slices) {
      vals <- unlist(s$resolvedValues); vars <- unlist(s$resolvedVariables)
      lines <- c(lines, paste0("Slice '", s$name, "':"))
      for (d in names(vals)) {
        v <- if (nzchar(vals[[d]])) vals[[d]] else "(no filter)"
        on <- if (d %in% names(vars)) paste0(" on ", vars[[d]]) else ""
        lines <- c(lines, paste0("  ", d, " = ", v, on))
      }
    }
    ov <- r$overrides
    c(lines, paste0("Overrides: ", if (length(ov)) paste(names(ov), unlist(ov), sep = " -> ", collapse = ", ") else "none")) |>
      paste(collapse = "\n")
  })

  output$step1 <- renderText(sprintf("%s records, %d variables%s", format(nrow(adlb()), big.mark = ","),
                                     ncol(adlb()), if (input$order == "latest") ", sorted latest date first" else ""))

  output$step3 <- renderTable({
    d <- derived()
    kept <- d[d$Subject == SUBJECT & d$Parameter == "Alanine Aminotransferase",
              "Measure.Result.Value__parameter_baseline"][1]
    x <- adlb_file[adlb_file$USUBJID == SUBJECT & adlb_file$PARAM == "Alanine Aminotransferase" &
                   adlb_file$AVISIT == "Baseline", c("VISIT", "ADT", "AVAL", "ABLFL")]
    x$ADT <- format(x$ADT); x$ABLFL[is.na(x$ABLFL)] <- ""
    x$`kept by the engine` <- ifelse(x$AVAL == kept, "yes", "")
    x
  })

  output$step4 <- renderTable({
    r <- run(); if (is.null(r$roles)) return(NULL)
    data.frame(role = names(r$roles), column = unname(r$roles))
  })

  output$step5 <- renderUI({
    r <- run()
    if (not_reached("slice")) return(p(class = "skip", "Not reached."))
    tagList(pre(paste(arrows(trimws(r$filters)), collapse = "\n")),
            failed_at("slice"),
            if (!is.null(r$cube)) p(sprintf("%d records, one per subject.", nrow(r$cube))))
  })

  output$step6 <- renderUI({
    r <- run()
    if (!is.null(r$failed) && r$failed != "fit") return(p(class = "skip", "Not reached."))
    if (!is.null(r$failed)) return(failed_at("fit"))
    pre(r$model)
  })

  output$step6table <- renderTable({
    ct <- run()$contrast; if (is.null(ct)) return(NULL)
    data.frame(Comparison = ct$Contrast, Estimate = sprintf("%.3f", ct$estimate),
               SE = sprintf("%.3f", ct$SE), `95% CI` = sprintf("%.2f to %.2f", ct$CI_lower, ct$CI_upper),
               df = as.integer(ct$df), `p value` = sprintf("%.3f", ct$p_value), check.names = FALSE)
  })

  output$step7 <- renderUI({
    r <- run()
    if (is.null(r$contrast)) return(p(class = "skip", "Not reached."))
    cov <- r$roles[["covariate"]]
    what <- if (cov == "BASE") "ADaM's BASE, the record TORIVA flags (ABLFL = Y)" else
      sprintf("%s, the value at the analysis visit itself, which the change is computed from", cov)
    tagList(p("Response: the value minus the engine's baseline, whichever record it finds first in the window."),
            p(paste0("Covariate: ", what, ".")),
            p(sprintf("For %d of %d subjects the engine's baseline differs from ADaM's BASE.",
                      r$n_differ, r$n_both)))
  })
}

shinyApp(ui, server)

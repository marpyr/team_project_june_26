server <- function(input, output, session) {

    # Define color palette
    pal <- colorFactor(
        palette = c("#fee5d9", "#fcae91", "#fb6a4a", "#cb181d"),
        levels  = c(0, 1, 2, 3)
    )

    # Map
    #----

    # select data by selected date
    # but define first date to be selected by default
    selected_date <- reactiveVal(unique_dates_US[1])

    observeEvent(input$btn_date_clicked, {
        selected_date(unique_dates_US[input$btn_date_clicked])
        session$sendCustomMessage("setActiveBtn", input$btn_date_clicked) })

    map_data <- reactive({
        shp_distr |>
            left_join(impacts |> filter(timestep == selected_date()),
                      by = c("BEZNAME" = "district")) })

    # render base map once
    output$heat_map <- renderLeaflet({
        leaflet(map_data()) |>
            addProviderTiles(providers$CartoDB.Positron) |>
            htmlwidgets::onRender("
    function(el, x) {
        var style = document.createElement('style');
        style.innerHTML = `
            .leaflet-control.info.legend {
                font-size: 40px !important;
                line-height: 1.4em !important;
            }
            .leaflet-control.info.legend i {
                width: 40px !important;
                height: 40px !important;
                margin-right: 6px !important;
                vertical-align: middle !important;
                display: inline-block !important;
                flex-shrink: 0 !important;
            }
            .leaflet-control.info.legend br {
                display: block !important;
            }
            .leaflet-control.info.legend > div {
                display: flex !important;
                flex-direction: column !important;
                gap: 8px !important;
            }
            .leaflet-control.info.legend > div > * {
                display: flex !important;
                flex-direction: row !important;
                align-items: center !important;
            }
        `;
        document.head.appendChild(style);
    }") |>
            addPolygons(
                fillColor   = ~pal(risk),
                fillOpacity = 0.8,
                color       = "#FFFFFF",
                weight      = 1.2,
                layerId     = ~BEZNAME,
                label       = ~paste0(BEZNAME, ": risk = ", risk),
                highlightOptions = highlightOptions(
                    weight       = 2,
                    color        = "#555555",
                    fillOpacity  = 0.9,
                    bringToFront = TRUE
                ),
                group = "districts"
            ) |>
            addLegend(
                position = "topright",
                colors   = c("#fee5d9", "#fcae91", "#fb6a4a", "#cb181d"),
                labels   = c("None", "Low", "Medium", "High"),
                title    = "Risk level",
                opacity  = 0.8
            )
    })

    # update polygons when date changes without redrawing map
    observe({
        leafletProxy("heat_map", data = map_data()) |>
            clearGroup("districts") |>
            addPolygons(
                fillColor   = ~pal(risk),
                fillOpacity = 0.8,
                color       = "#FFFFFF",
                weight      = 1.2,
                layerId     = ~BEZNAME,
                label = ~paste0(BEZNAME, ": ", dplyr::case_when(
                    risk == 0 ~ "None",
                    risk == 1 ~ "Low",
                    risk == 2 ~ "Medium",
                    risk == 3 ~ "High",
                    TRUE ~ "Unknown"
                )),
                labelOptions = labelOptions(
                    style    = list("font-size" = "22px", "font-weight" = "bold", "padding" = "6px 10px"),
                    textsize = "22px"
                ),
                highlightOptions = highlightOptions(
                    weight       = 2,
                    color        = "#555555",
                    fillOpacity  = 0.9,
                    bringToFront = TRUE
                ),
                group = "districts"
            )

        # re-apply highlight if a district is already selected
        if (!is.null(selected_address_data())) {
            matched_district <- selected_address_data()$district[1]
            matched_geom <- map_data() |>
                filter(BEZNAME == matched_district)

            leafletProxy("heat_map") |>
                clearGroup("highlight") |>
                addPolygons(
                    data        = matched_geom,
                    fillColor   = "transparent",
                    fillOpacity = 0,
                    color       = "black",
                    weight      = 5.5,
                    opacity     = 1,
                    group       = "highlight"
                ) }  })

    # clicked district data to display as barplot
    clicked_district_data <- reactiveVal(NULL) # no default

    observeEvent(input$heat_map_shape_click, {
        click <- input$heat_map_shape_click
        req(click$id)

        district_all_dates <- impacts |>
            filter(district == click$id)

        clicked_district_data(district_all_dates)
        cat("District:", click$id, "\n")
    })

    observeEvent(input$heat_map_shape_click, {
        click <- input$heat_map_shape_click
        req(click$id)

        # use clicked district to update barplot and highlight
        district_all_dates <- impacts |>
            filter(district == click$id)

        # troubleshooting
        if (nrow(district_all_dates) > 0) {
            selected_address_data(district_all_dates)
            cat("Map click — district:", click$id, "\n")
        } else {
            cat("Map click — no data found for:", click$id, "\n")
        } })

    #----

    # Address search
    #----

    # debounce so we don't fire on every keystroke
    address_debounced <- debounce(reactive(input$address_input), 600)

    # query Nominatim for suggestions
    address_results <- reactive({
        req(nchar(address_debounced()) > 4)

        url <- paste0(
            "https://nominatim.openstreetmap.org/search?q=",
            utils::URLencode(address_debounced()),
            "&countrycodes=ch&format=json&addressdetails=1&limit=5"
        )

        response <- httr::GET(url, httr::user_agent("heat_risk_app"))
        jsonlite::fromJSON(httr::content(response, as = "text"))
    })

    # render clickable suggestions
    output$address_suggestions <- renderUI({
        res <- address_results()
        req(nrow(res) > 0)

        tags$div(
            style = "border: 1px solid #ddd; border-radius: 6px; overflow: hidden;",
            lapply(seq_len(nrow(res)), function(i) {
                actionButton(
                    inputId = paste0("addr_btn_", i),
                    label   = res$display_name[i],
                    class   = "addr-suggestion"
                ) }) ) })

    # when user clicks a suggestion, extract district and look up data
    selected_address_data <- reactiveVal(
        impacts |> filter(district == "Verwaltungskreis Bern-Mittelland"))

    observe({
        res <- address_results()
        req(nrow(res) > 0)

        lapply(seq_len(nrow(res)), function(i) {
            observeEvent(input[[paste0("addr_btn_", i)]], {

                # print all available address fields to console
                # cat("Full address fields:\n")
                # print(as.data.frame(res$address[i, ]))

                nominatim_district <- dplyr::coalesce(
                    res$address$county[i],
                    res$address$state_district[i],
                    res$address$city[i],
                    res$address$municipality[i],
                    res$address$town[i],
                    res$address$state[i]
                )

                # cat("Nominatim county:", nominatim_district, "\n")

                # guard against empty or NA county
                if (is.null(nominatim_district) || is.na(nominatim_district) || nchar(trimws(nominatim_district)) == 0) {
                    cat("No county found in Nominatim response — trying state_district\n")
                    nominatim_district <- res$address$state_district[i]
                }

                req(nchar(trimws(nominatim_district)) > 0)

                matched <- shp_distr |>
                    st_drop_geometry() |>
                    filter(
                        stringr::str_detect(BEZNAME, stringr::fixed(nominatim_district, ignore_case = TRUE)) |
                            stringr::str_detect(nominatim_district, stringr::fixed(BEZNAME, ignore_case = TRUE))
                    ) |>
                    pull(BEZNAME) |>
                    first()

                if (!is.na(matched)) {
                    district_all_dates <- impacts |> filter(district == matched)
                    selected_address_data(district_all_dates)
                    cat("Matched to:", matched, "\n")
                } else {
                    cat("No match found for:", nominatim_district, "\n")
                }
                updateTextInput(session, "address_input", value = "")
            }, ignoreInit = TRUE)
        })
    })

    #----

    # Barplot
    #----

    output$risk_plot <- renderPlot({
        req(selected_address_data())

        selected_address_data() |>
            mutate(timestep = as.Date(timestep)) |>
            ggplot(aes(x = timestep, y = 1)) +
            geom_col(aes(fill = factor(risk)), color = "black", width = 1, linewidth = 2.4,
                     show.legend = FALSE, alpha = 0.8) +
            scale_fill_manual(values = c(
                "0" = "#fee5d9",
                "1" = "#fcae91",
                "2" = "#fb6a4a",
                "3" = "#cb181d"
            )) +
            lims(y = c(0, 1)) +
            scale_x_date(date_labels = "%d %b", date_breaks = "1 day") +
            labs(
                title = paste0(selected_address_data()$district[1]),
            ) +
            theme_minimal() +
            theme(
                axis.ticks = element_blank(),
                axis.text.x      = element_text(angle = 0, hjust = .5, vjust = 1,
                                                size = 30, face = "bold"),
                plot.title       = element_text(size = 35, face = "bold", hjust = 0.12),
                axis.title       = element_blank(),
                axis.text.y      = element_blank(),
                panel.grid.major = element_blank(),
                panel.grid.minor = element_blank(),
                plot.margin      = margin(t = 20, r = 10, b = 60, l = 10)
            )
    })

    observeEvent(selected_address_data(), {
        req(selected_address_data())

        matched_district <- selected_address_data()$district[1]

        matched_geom <- map_data() |>
            filter(BEZNAME == matched_district)

        leafletProxy("heat_map") |>
            clearGroup("highlight") |>
            addPolygons(
                data        = matched_geom,
                fillColor   = "transparent",
                fillOpacity = 0,
                color       = "black",
                weight      = 5.5,
                opacity     = 1,
                group       = "highlight"
            )
    })

    #----

}

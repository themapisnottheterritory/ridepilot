# Fares (FY27, effective September 1, 2026)

All fares are one way. The same fare table applies in every county, including Goliad and Lavaca.

**Rural demand response, by trip miles**

| Miles | Under 5 | Youth 5-17 | Adult 18-59 | Elderly/Disabled 60+ |
|---|---|---|---|---|
| 0-5 | Free | $0.75 | $1.00 | $0.50 |
| 6-10 | Free | $1.75 | $2.00 | $1.00 |
| 11-15 | Free | $2.00 | $3.00 | $1.50 |
| 16-20 | Free | $2.50 | $4.00 | $2.00 |
| 21+ | Free | $3.00 | $5.00 | $2.50 |

- **ADA paratransit** (riders certified ADA eligible, in Victoria): $1.50 flat.
- **Fixed route** (city buses): Under 5 free with a paying adult, Youth $0.75, Adult $1.00, Elderly/Disabled $0.50.
- **Personal care attendant (PCA)**: rides free.
- **Companion or guest**: pays the same fare as the rider they travel with.
- **Gonzales County**: rides are free through September 30, 2026; fares start October 1, 2026.

**How RidePilot works out a trip's fare**: from the trip's driving distance and the rider's category, in this order: the customer's **Fare category**; if that's not set, a trip marked Disabled or Senior under **Number of Passengers Tracking**; then the customer's Elderly? box; otherwise Adult (the "Fare to quote" panel then warns that Adult was assumed). An amount typed in the trip's Fare Configurations Payment box overrides the table.

**On the driver's tablet**: the pickup stop shows a Fare box pre-filled with the fare; the driver collects cash and taps Collect Fare, or corrects the amount first.

**Rides with no fare (Lavaca: Title III and New Horizons)**: some funding sources pay for the whole ride, so the rider pays nothing. Lavaca has two: **Title III** and **New Horizons**; those rides are passed through to them, and the rider is never asked for a fare. Choose the right one as the trip's **Funding Source** (or set it as the customer's default funding source, so every new trip gets it). The trip form's fare panel then says **No fare**, Dispatch and the printed manifest say **no fare**, and the driver's tablet shows no Fare box and a note on the pickup, such as "NO FARE: paid by Title III. Don't collect a fare."

**Fares Collected report (match a driver's cash to the tablet)**: **Reports > Fares Collected**. Pick the dates and group by **Driver**, **Run** or **Day**. It lists every fare a driver recorded on the tablet (**Collect Fare**, a fare card, or a monthly pass), with cash and fare card totals for each driver or run, then each fare with its time, run, driver, rider and funding source. Choose CSV to download it for Excel. A fare the driver took but never tapped **Collect Fare** for isn't in it.

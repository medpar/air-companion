# Analysis methods and limits

## Training load

Session RPE uses the athlete's whole-session perceived effort (0–10) multiplied
by minutes. Air Companion shows arbitrary units and calendar-week totals; missing
RPE is excluded, not zero. Rate the whole session, ideally around 30 minutes
later. This subjective load complements other observations and is not a diagnosis
or a validated prediction of injury.

[Foster et al., 2001, A new approach to monitoring exercise training](https://pubmed.ncbi.nlm.nih.gov/11708692/).

## HRV and resting heart rate

[HealthKit's HRV quantity is SDNN](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn),
not RMSSD. The app averages positive samples per local day and per source/device.
Recording duration, posture, breathing, artifacts and time of day affect HRV;
values from different devices or methods are not interchangeable.

[Task Force, 1996, HRV measurement standards](https://pubmed.ncbi.nlm.nih.gov/8598068/)
and [Catai et al., standardisation checklist](https://pubmed.ncbi.nlm.nih.gov/30852243/).

The app's 7/28-day windows and minimum coverage rules are transparent product
choices, **not a separately validated physiological algorithm**. They describe
changes. There is no “recovery percent” or medical interpretation. Selecting a
different source starts a different comparison, not a blended baseline.

## Sleep

The importer uses HealthKit asleep-unspecified, core, deep and REM stages. It
excludes in-bed and awake entries, merges overlaps within one source, and splits
at local noon to group an overnight sleep episode under its morning date. Naps
can contribute to the same sleep day. Calendar boundaries avoid DST errors.
This produces recorded asleep duration, not sleep efficiency or a clinical sleep
score. Missing coverage, wearable classification error and incomplete app exports
remain limitations.

## Steps and heart rate from Air

These are explicit refresh snapshots. Heart rate is shown only for the recovered
confidence values 2/3. The band timestamp's units have not been established, so
samples are labelled with phone read time. Old steps are never presented as today's
total. A stored daily snapshot can undercount the final day if the last refresh
was early. No step history is fabricated between refreshes.

## Health access and storage

[Apple HealthKit setup](https://developer.apple.com/documentation/healthkit/setting-up-healthkit).
Authorization is user-driven and read-only. Apple deliberately does not disclose
whether an empty result means denial or no data. The importer makes a bounded
60-day query, fails rather than accepting more than 20,000 samples per type, and
keeps the previous library if a query fails. Empty metric types preserve their
previous imported history because an empty result cannot distinguish denied
access from no data. Revoking permission does not delete
previously imported samples; the app includes a local removal control.

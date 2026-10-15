# Analysis methods and limits

Pebble describes change against a person's own history. It does not diagnose,
score readiness or predict injury. Missing days are never treated as zero, and
values from different Apple Health sources are never blended.

## Usual range

The recent value is the mean of the last 7 completed local days. The usual range
comes from the 60 days before that week. A range needs at least 4 recent and
14 earlier days.

- **HRV** is log-transformed and the range is the baseline mean ± 0.5 SD, the
  "smallest worthwhile change" used for rolling HRV monitoring
  ([Plews et al., 2013](https://pubmed.ncbi.nlm.nih.gov/?term=Plews+2013+training+adaptation+heart+rate+variability+elite+endurance+athletes)).
  Apple Health stores SDNN, not RMSSD
  ([HealthKit](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn)),
  so values differ from RMSSD-based apps. Recording conditions matter
  ([Task Force, 1996](https://pubmed.ncbi.nlm.nih.gov/8598068/)).
- **Resting heart rate and sleep duration** use the baseline mean ± 1 SD.
- Positions are judged at display precision, so a value is never called outside
  a range it appears to sit on.

## Sleep

Asleep stages (unspecified, core, deep, REM) from one source are merged in local
noon-to-noon windows keyed by the morning date; in-bed and awake entries are
excluded. Duration is total asleep time. Timing is the midpoint of the main
sleep episode (blocks closer than 60 minutes joined; at least 3 hours).
Regularity is the standard deviation of that midpoint over 14 nights. Adults are
advised to sleep at least 7 hours
([Watson et al., 2015](https://pubmed.ncbi.nlm.nih.gov/?term=Watson+2015+recommended+amount+of+sleep+for+a+healthy+adult+consensus)),
and irregular timing is associated with poorer outcomes independent of duration
([Phillips et al., 2017](https://pubmed.ncbi.nlm.nih.gov/?term=Phillips+2017+irregular+sleep+wake+patterns+academic+performance+delayed+circadian)).

## Training

- **Load** = whole-session RPE (0–10) × minutes
  ([Foster et al., 2001](https://pubmed.ncbi.nlm.nih.gov/11708692/)). Unrated
  sessions are excluded, not zero.
- **Fitness and fatigue** are exponentially weighted daily loads with 42- and
  7-day time constants; **form** = fitness − fatigue (Banister impulse-response
  model, 1975). Values are in arbitrary units of the person's own load.
- **Live sessions** with Heart Rate Profile data record time in five
  heart-rate-reserve zones (Karvonen; floors at 50/60/70/80/90 %) and an Edwards
  summated-zone load (minutes × zone number). RMSSD is shown from the last 120
  RR intervals when the band supplies them.

## Cardio fitness

VO₂max ≈ 15.3 × HRmax / HRrest
([Uth et al., 2004](https://pubmed.ncbi.nlm.nih.gov/?term=Uth+2004+estimation+of+VO2max+from+the+ratio+between+HRmax+and+HRrest)).
HRmax = 208 − 0.7 × age
([Tanaka et al., 2001](https://pubmed.ncbi.nlm.nih.gov/?term=Tanaka+Monahan+Seals+2001+age-predicted+maximal+heart+rate+revisited))
unless a measured value is entered. Population estimate; individual error is
roughly 10–15 %.

## Steps and movement

- Band step counts are timestamped snapshots; old counts are never shown as
  today's. Apple Health steps use Health's own de-duplicated daily sums per source.
- About 100 steps/min marks moderate-intensity walking
  ([Tudor-Locke et al., 2018](https://pubmed.ncbi.nlm.nih.gov/?term=Tudor-Locke+2018+walking+cadence+steps+per+minute+moderate+intensity)),
  used for the minutes-to-goal estimate.
- Goal guidance: mortality benefits level off around 8,000–10,000 daily steps
  under 60 and 6,000–8,000 from 60
  ([Paluch et al., 2022](https://pubmed.ncbi.nlm.nih.gov/?term=Paluch+2022+daily+steps+and+all-cause+mortality+meta-analysis)).
- The move reminder fires after an hour inside active hours with fewer steps
  than the threshold, at most once every two clock hours. Breaking up sitting
  with light walking improves post-meal glucose and insulin
  ([Dunstan et al., 2012](https://pubmed.ncbi.nlm.nih.gov/?term=Dunstan+2012+breaking+up+prolonged+sitting+postprandial+glucose+insulin)).

## Alerts and checks

Goal and milestone alerts fire once per local day. Several milestones crossed
between checks produce one buzz. Every delivery is journaled before it runs, so a
relaunch or repeated reading never replays it. Band checks are scheduled
adaptively: sooner when the recent pace is about to cross a threshold (never under
5 minutes), otherwise every 30–60 minutes. This keeps time away from Google
Health to a minimum.

## Health access and storage

Authorization is user-driven and read-only. Apple doesn't reveal whether an empty
result means denial or no data, so empty metric types keep their previous
history. Imports cover 90 days and reject more than 20,000 samples per type.

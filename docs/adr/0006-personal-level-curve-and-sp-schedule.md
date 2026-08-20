# Fixed Personal XP anchors; cubic curve; data-driven SP grants

Personal Level thresholds are fixed Personal XP totals (design anchors: L1 = 375, L10 = 10 500, L100 = 2 089 350), not recalculated from weighted “max all skills.” Earn rate is controlled by per-skill Personal XP weights (and traits/SP play). Between anchors, cumulative XP follows a smooth cubic fitted to those three points. Default SP grant is 1 per Personal Level gained, starting from Personal Level 0; the grant schedule is data-driven so later tuning can add milestone lumps or skip grants without changing the domain model.

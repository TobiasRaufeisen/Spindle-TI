# GLMM analysis of spindle temporal distribution across stimulation
# conditions. Models binary spindle occurrence (0/1) per
# subject x electrode x trial x time-bin observation with a binomial-logit
# GLMM (lme4::glmer, ML, Laplace). Fits models of increasing complexity
# (M0--M5), selects the best by AIC, runs post-hoc contrasts, DHARMa
# diagnostics, and aggregated-density sensitivity analyses; writes
# per-model tables, supplementary tables, and figures to outputs/.

if (!require("pacman")) install.packages("pacman")
pacman::p_load(
  lme4, lmerTest, car, emmeans, multcomp, DHARMa, sjPlot, performance,
  ggplot2, dplyr, tidyr, effects, ggeffects, MuMIn, broom.mixed, knitr
)

options(contrasts = c("contr.sum", "contr.poly"))   # Type III SS
options(scipen = 999)

# Resolve outputs/ next to this script (works via Rscript, source(), or RStudio).
get_script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", args, value = TRUE)
  if (length(file_arg) == 1) return(dirname(normalizePath(sub("^--file=", "", file_arg))))
  of <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (!is.null(of)) return(dirname(normalizePath(of)))
  if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable())
    return(dirname(rstudioapi::getActiveDocumentContext()$path))
  getwd()
}
output_dir <- file.path(get_script_dir(), "outputs")
data_file  <- file.path(output_dir, "comprehensive_trial_level_data_GLMM_ready.csv")

dat <- read.csv(data_file, stringsAsFactors = FALSE)
dat$Subject   <- factor(dat$Subject)
dat$Condition <- factor(dat$Condition, levels = c("OFF", "x1HZ", "x5HZ"))
dat$TimeBin   <- factor(dat$TimeBin, ordered = FALSE)
dat$Electrode <- factor(dat$Electrode)
dat$Trial     <- factor(dat$Trial)
dat$Spindle   <- as.integer(dat$Spindle)
dat <- dat[!is.na(dat$Condition), ]
dat$SubjElec          <- interaction(dat$Subject, dat$Electrode)
dat$CondTimeBin       <- interaction(dat$Condition, dat$TimeBin)
dat$BinCenterCentered <- dat$BinCenter - mean(dat$BinCenter)

colors      <- c("OFF" = "#999999", "x1HZ" = "#003399", "x5HZ" = "#FF8C00")
cond_labels <- c("OFF" = "OFF",     "x1HZ" = "1 Hz",    "x5HZ" = "5 Hz")

desc_stats <- dat %>%
  group_by(Condition, TimeBin, BinCenter) %>%
  summarise(N_obs = n(), N_spindles = sum(Spindle),
            Proportion = mean(Spindle),
            SE = sqrt(Proportion * (1 - Proportion) / N_obs),
            .groups = "drop") %>%
  arrange(Condition, TimeBin)

subj_stats <- dat %>%
  group_by(Subject, Condition, TimeBin, BinCenter) %>%
  summarise(Proportion = mean(Spindle), .groups = "drop")

# Progressive GLMMs (binomial / logit).
glmer_ctrl  <- glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))
glmer_ctrl5 <- glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 3e5))

m0 <- glmer(Spindle ~ Condition + (1 | Subject) + (1 | Electrode),
            data = dat, family = binomial(link = "logit"), control = glmer_ctrl)
m0_anova <- car::Anova(m0, type = "III")

m1 <- glmer(Spindle ~ Condition + TimeBin + (1 | Subject),
            data = dat, family = binomial(link = "logit"), control = glmer_ctrl)
m2 <- glmer(Spindle ~ Condition * TimeBin + (1 | Subject),
            data = dat, family = binomial(link = "logit"), control = glmer_ctrl)
m3 <- glmer(Spindle ~ Condition * TimeBin + (1 | Subject) + (1 | Electrode),
            data = dat, family = binomial(link = "logit"), control = glmer_ctrl)
m4 <- tryCatch(
  glmer(Spindle ~ Condition * TimeBin + (1 | Subject) + (1 | Subject:Electrode),
        data = dat, family = binomial(link = "logit"), control = glmer_ctrl),
  error = function(e) NULL)
m5 <- tryCatch(
  glmer(Spindle ~ Condition * TimeBin + (Condition | Subject) + (1 | Electrode),
        data = dat, family = binomial(link = "logit"), control = glmer_ctrl5),
  error = function(e) NULL)

model_list <- list(
  "M0: Condition only" = m0,
  "M1: Main effects"   = m1,
  "M2: Interaction"    = m2,
  "M3: +Electrode RE"  = m3
)
if (!is.null(m4)) model_list[["M4: +Subj:Elec RE"]]   <- m4
if (!is.null(m5)) model_list[["M5: +Condition slope"]] <- m5

comparison  <- compare_performance(model_list, rank = TRUE)
lrt_m1_m2   <- anova(m1, m2)
lrt_m2_m3   <- anova(m2, m3)
lrt_m3_m4   <- if (!is.null(m4)) anova(m3, m4) else NULL

best_model_idx  <- which.min(sapply(model_list, AIC))
best_model_name <- names(model_list)[best_model_idx]
best_model      <- model_list[[best_model_idx]]

anova_results <- car::Anova(best_model, type = "III")

emm <- emmeans(best_model, ~ Condition * TimeBin, type = "response")
contrast_cond_by_bin         <- contrast(emm, method = "pairwise",
                                          by = "TimeBin",   adjust = "fdr")
contrast_cond_by_bin_summary <- summary(contrast_cond_by_bin)
contrast_bin_by_cond         <- contrast(emm, method = "pairwise",
                                          by = "Condition", adjust = "fdr")
contrast_bin_by_cond_summary <- summary(contrast_bin_by_cond)

pre_vs_post_contrasts <- list()
for (cond in c("OFF", "x1HZ", "x5HZ")) {
  cf <- list("Bin1_vs_Bin2" = c(1, -1, 0, 0, 0),
             "Bin1_vs_Bin3" = c(1, 0, -1, 0, 0),
             "Bin1_vs_Bin4" = c(1, 0, 0, -1, 0),
             "Bin1_vs_Bin5" = c(1, 0, 0, 0, -1))
  emm_cond <- emmeans(best_model, ~ TimeBin,
                       at = list(Condition = cond), type = "response")
  pre_vs_post_contrasts[[cond]] <- summary(
    contrast(emm_cond, method = cf, adjust = "fdr"), infer = TRUE)
}

fixed_effects <- fixef(best_model)
se_fixed      <- sqrt(diag(vcov(best_model)))
effect_sizes  <- data.frame(
  Parameter      = names(fixed_effects),
  Estimate_logOR = fixed_effects,
  SE             = se_fixed,
  OR             = exp(fixed_effects),
  OR_CI_lower    = exp(fixed_effects - 1.96 * se_fixed),
  OR_CI_upper    = exp(fixed_effects + 1.96 * se_fixed),
  z_value        = fixed_effects / se_fixed,
  p_value        = 2 * (1 - pnorm(abs(fixed_effects / se_fixed)))
)

simulated_residuals <- simulateResiduals(fittedModel = best_model, n = 500, plot = FALSE)
uniformity_test     <- testUniformity(simulated_residuals)
dispersion_test     <- testDispersion(simulated_residuals)
zeroinflation_test  <- testZeroInflation(simulated_residuals)
outlier_test        <- testOutliers(simulated_residuals, type = "bootstrap")
best_model_varcorr  <- VarCorr(best_model)
best_model_ranef    <- ranef(best_model, condVar = TRUE)

# LMM on electrode-aggregated densities (sensitivity).
dat_agg <- dat %>%
  group_by(Subject, Condition, TimeBin, BinCenter, Electrode) %>%
  summarise(SpindleDensity = mean(Spindle), N_trials = n(), .groups = "drop")
lmm1 <- lmer(SpindleDensity ~ Condition + TimeBin + (1 | Subject),
             data = dat_agg, REML = TRUE)
lmm2 <- lmer(SpindleDensity ~ Condition * TimeBin + (1 | Subject),
             data = dat_agg, REML = TRUE)
lmm3 <- lmer(SpindleDensity ~ Condition * TimeBin + (1 | Subject) + (1 | Electrode),
             data = dat_agg, REML = TRUE)
lmm_comparison       <- anova(lmm1, lmm2, lmm3)
best_lmm             <- lmm3
lmm_anova            <- anova(best_lmm, type = "III", ddf = "Kenward-Roger")
emm_lmm              <- emmeans(best_lmm, ~ Condition * TimeBin)
contrast_lmm         <- contrast(emm_lmm, method = "pairwise",
                                 by = "TimeBin", adjust = "fdr")
contrast_lmm_summary <- summary(contrast_lmm)
lmm_model_list <- list("LMM1: Main effects"  = lmm1,
                       "LMM2: Interaction"   = lmm2,
                       "LMM3: +Electrode RE" = lmm3)

# Further sensitivity: collapse electrodes to subject-level proportions.
dat_subj <- dat %>%
  group_by(Subject, Condition, TimeBin, BinCenter) %>%
  summarise(SpindleProp = mean(Spindle), .groups = "drop")
lmm_subj         <- lmer(SpindleProp ~ Condition * TimeBin + (1 | Subject),
                          data = dat_subj, REML = TRUE)
lmm_subj_summary <- summary(lmm_subj)
lmm_subj_anova   <- anova(lmm_subj, type = "III", ddf = "Kenward-Roger")

emm_boot         <- emmeans(best_model, ~ Condition * TimeBin, type = "response")
contrast_boot    <- contrast(emm_boot, method = "pairwise", by = "TimeBin")
contrast_boot_ci <- confint(contrast_boot, method = "profile")

power_analysis <- desc_stats %>%
  pivot_wider(names_from = Condition,
              values_from = c(Proportion, SE, N_obs)) %>%
  mutate(
    Effect_x5HZ_vs_OFF = Proportion_x5HZ - Proportion_OFF,
    SE_diff            = sqrt(SE_x5HZ^2 + SE_OFF^2),
    Cohens_h           = 2 * (asin(sqrt(Proportion_x5HZ)) -
                              asin(sqrt(Proportion_OFF))),
    Effect_x1HZ_vs_OFF = Proportion_x1HZ - Proportion_OFF
  ) %>%
  select(TimeBin, BinCenter, Effect_x5HZ_vs_OFF, Effect_x1HZ_vs_OFF, Cohens_h)

# Per-model EMMs/contrasts cached for use by both the report and the CSV
# exports. M0 has no TimeBin term, so its EMM table is keyed on Condition only.
glmm_model_results <- list()
for (mname in names(model_list)) {
  m_cur <- model_list[[mname]]
  res <- list(
    summary_obj = summary(m_cur),
    varcorr     = VarCorr(m_cur),
    formula     = formula(m_cur),
    aic         = AIC(m_cur),
    bic         = BIC(m_cur),
    anova_III   = tryCatch(car::Anova(m_cur, type = "III"),
                            error = function(e) NULL)
  )
  res$emm_data <- if (mname == "M0: Condition only") {
    tryCatch({
      emm_tmp <- emmeans(m_cur, ~ Condition, type = "response")
      list(emm_summary   = summary(emm_tmp),
           contrast_cond = summary(contrast(emm_tmp, method = "pairwise",
                                             adjust = "fdr")))
    }, error = function(e) NULL)
  } else {
    tryCatch({
      emm_tmp <- emmeans(m_cur, ~ Condition * TimeBin, type = "response")
      list(emm_summary   = summary(emm_tmp),
           contrast_cond = summary(contrast(emm_tmp, method = "pairwise",
                                             by = "TimeBin", adjust = "fdr")),
           contrast_bin  = summary(contrast(emm_tmp, method = "pairwise",
                                             by = "Condition", adjust = "fdr")))
    }, error = function(e) NULL)
  }
  glmm_model_results[[mname]] <- res
}

lmm_model_results <- list()
for (lmm_name in names(lmm_model_list)) {
  lmm_cur <- lmm_model_list[[lmm_name]]
  lmm_model_results[[lmm_name]] <- list(
    summary_obj = summary(lmm_cur),
    formula     = formula(lmm_cur),
    aic         = AIC(lmm_cur),
    bic         = BIC(lmm_cur),
    anova_III   = tryCatch(anova(lmm_cur, type = "III", ddf = "Kenward-Roger"),
                            error = function(e) NULL),
    emm_data    = tryCatch({
      emm_tmp <- emmeans(lmm_cur, ~ Condition * TimeBin)
      list(emm_summary   = summary(emm_tmp),
           contrast_cond = summary(contrast(emm_tmp, method = "pairwise",
                                             by = "TimeBin", adjust = "fdr")))
    }, error = function(e) NULL)
  )
}

p_to_stars <- function(p) ifelse(p < 0.001, "***",
                          ifelse(p < 0.01,  "**", "*"))

# EMM-barplot prep: use M5 if it converged, else best model.
emm_plot_model <- if (!is.null(m5)) m5 else best_model
emm_plot_data  <- emmeans(emm_plot_model, ~ Condition * TimeBin, type = "response")
emm_df         <- as.data.frame(summary(emm_plot_data))
bin_mapping    <- dat %>% select(TimeBin, BinCenter) %>% distinct() %>%
                   arrange(TimeBin)
emm_df         <- merge(emm_df, bin_mapping, by = "TimeBin")

emm_pairs_by_bin <- contrast(emm_plot_data, method = "pairwise",
                              by = "TimeBin", adjust = "fdr")
emm_pairs_df     <- as.data.frame(summary(emm_pairs_by_bin))
sig_pairs        <- emm_pairs_df[emm_pairs_df$p.value < 0.05, ]

if (nrow(sig_pairs) > 0) {
  sig_pairs          <- merge(sig_pairs, bin_mapping, by = "TimeBin")
  sig_pairs$contrast <- as.character(sig_pairs$contrast)
  sig_pairs$cond1    <- trimws(sub(" [-/] .*", "", sig_pairs$contrast))
  sig_pairs$cond2    <- trimws(sub(".* [-/] ",  "", sig_pairs$contrast))
  sig_pairs$stars    <- p_to_stars(sig_pairs$p.value)

  dodge_width  <- 0.8
  cond_offsets <- c("OFF"  = -dodge_width / 3,
                    "x1HZ" =  0,
                    "x5HZ" =  dodge_width / 3)
  bin_levels   <- sort(unique(emm_df$BinCenter))
  sig_pairs$x_num   <- match(sig_pairs$BinCenter, bin_levels)
  sig_pairs$x_start <- sig_pairs$x_num + cond_offsets[sig_pairs$cond1]
  sig_pairs$x_end   <- sig_pairs$x_num + cond_offsets[sig_pairs$cond2]

  max_y         <- max(emm_df$asymp.UCL, na.rm = TRUE)
  bracket_step  <- max_y * 0.07
  sig_pairs     <- sig_pairs[order(sig_pairs$BinCenter,
                                    abs(sig_pairs$x_end - sig_pairs$x_start)), ]
  sig_pairs$bracket_idx <- ave(seq_len(nrow(sig_pairs)),
                                sig_pairs$BinCenter, FUN = seq_along)
  sig_pairs$y_bracket   <- max_y * 1.05 +
                            (sig_pairs$bracket_idx - 1) * bracket_step
}

cld_df <- tryCatch({
  cld_result <- multcomp::cld(emm_plot_data, by = "TimeBin",
                               adjust = "fdr", Letters = letters)
  cld_tmp    <- merge(as.data.frame(cld_result), bin_mapping, by = "TimeBin")
  cld_tmp$.group <- trimws(cld_tmp$.group)
  cld_tmp
}, error = function(e) NULL)

# M0 (condition-only) EMM data; display order matches the MATLAB barplot.
m0_cond_order   <- c("x5HZ", "x1HZ", "OFF")
m0_cond_display <- c("x5HZ" = "5 Hz", "x1HZ" = "1 Hz", "OFF" = "Off")

emm_m0    <- emmeans(m0, ~ Condition, type = "response")
emm_m0_df <- as.data.frame(summary(emm_m0))
emm_m0_df$Condition <- factor(emm_m0_df$Condition, levels = m0_cond_order)

subj_m0 <- subj_stats %>%
  group_by(Subject, Condition) %>%
  summarise(MeanProp = mean(Proportion, na.rm = TRUE), .groups = "drop")
subj_m0$Condition <- factor(subj_m0$Condition, levels = m0_cond_order)

subj_m0_summary <- subj_m0 %>%
  group_by(Condition) %>%
  summarise(Mean = mean(MeanProp, na.rm = TRUE),
            SD   = sd(MeanProp,   na.rm = TRUE),
            N    = n(),
            SEM  = SD / sqrt(N),
            .groups = "drop")

emm_m0_pairs    <- pairs(emm_m0, adjust = "holm")
emm_m0_pairs_df <- as.data.frame(summary(emm_m0_pairs))
sig_pairs_m0    <- emm_m0_pairs_df[emm_m0_pairs_df$p.value < 0.05, ]
m0_cond_p       <- tryCatch(
  m0_anova[["Pr(>Chisq)"]][rownames(m0_anova) == "Condition"],
  error = function(e) NA_real_
)

if (nrow(sig_pairs_m0) > 0) {
  sig_pairs_m0$contrast <- as.character(sig_pairs_m0$contrast)
  sig_pairs_m0$cond1    <- trimws(sub(" [-/] .*", "", sig_pairs_m0$contrast))
  sig_pairs_m0$cond2    <- trimws(sub(".* [-/] ",  "", sig_pairs_m0$contrast))
  sig_pairs_m0$stars    <- p_to_stars(sig_pairs_m0$p.value)
  sig_pairs_m0$x_start  <- match(sig_pairs_m0$cond1, m0_cond_order)
  sig_pairs_m0$x_end    <- match(sig_pairs_m0$cond2, m0_cond_order)
  max_y_m0   <- max(subj_m0$MeanProp, na.rm = TRUE)
  range_y_m0 <- diff(range(subj_m0$MeanProp, na.rm = TRUE))
  bracket_step_m0 <- range_y_m0 * 0.05
  sig_pairs_m0 <- sig_pairs_m0[order(abs(sig_pairs_m0$x_end -
                                          sig_pairs_m0$x_start)), ]
  sig_pairs_m0$bracket_idx <- seq_len(nrow(sig_pairs_m0))
  sig_pairs_m0$y_bracket   <- max_y_m0 * 1.15 +
                               (sig_pairs_m0$bracket_idx - 1) * bracket_step_m0
}

pred_data <- ggpredict(best_model, terms = c("TimeBin", "Condition"))


# --- Plots ---

p1 <- ggplot(desc_stats, aes(x = BinCenter, y = Proportion, fill = Condition)) +
  geom_bar(stat = "identity", position = position_dodge(width = 0.4),
           width = 0.35, alpha = 0.8) +
  geom_errorbar(aes(ymin = Proportion - SE, ymax = Proportion + SE),
                position = position_dodge(width = 0.4), width = 0.15) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray40") +
  scale_fill_manual(values = colors, labels = cond_labels) +
  labs(x = "Time from trial onset (s)", y = "Spindle probability",
       title = "Temporal Distribution of Spindles by Condition") +
  theme_classic(base_size = 12) +
  theme(legend.position = "right",
        legend.title    = element_text(face = "bold"))
ggsave(file.path(output_dir, "spindle_temporal_distribution.png"),
       p1, width = 8, height = 5, dpi = 300)

p2 <- ggplot(subj_stats, aes(x = BinCenter, y = Proportion,
                              color = Condition, group = Subject)) +
  geom_line(alpha = 0.4) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "gray40") +
  scale_color_manual(values = colors, labels = cond_labels) +
  facet_wrap(~ Condition, labeller = labeller(Condition = cond_labels)) +
  labs(x = "Time from trial onset (s)", y = "Spindle probability",
       title = "Individual Subject Trajectories") +
  theme_classic(base_size = 11) + theme(legend.position = "none")
ggsave(file.path(output_dir, "spindle_individual_trajectories.png"),
       p2, width = 10, height = 4, dpi = 300)

png(file.path(output_dir, "model_diagnostics_DHARMa.png"),
    width = 10, height = 5, units = "in", res = 300)
plot(simulated_residuals)
dev.off()

png(file.path(output_dir, "random_effects_caterpillar.png"),
    width = 8, height = 6, units = "in", res = 300)
lattice::dotplot(best_model_ranef)
dev.off()

p_emm_facet <- ggplot(emm_df, aes(x = factor(BinCenter), y = prob,
                                   fill = Condition)) +
  geom_bar(stat = "identity", width = 0.7, alpha = 0.85) +
  geom_errorbar(aes(ymin = asymp.LCL, ymax = asymp.UCL),
                width = 0.25, linewidth = 0.5) +
  facet_wrap(~ Condition, labeller = labeller(Condition = cond_labels)) +
  scale_fill_manual(values = colors, labels = cond_labels) +
  scale_y_continuous(expand = expansion(mult = c(0.02, 0.12))) +
  labs(x = "Time from trial onset (s)",
       y = "Estimated Spindle Probability",
       title    = "Model Estimates: Spindle Probability per Condition",
       subtitle = "Letters: conditions sharing a letter within a bin do not differ significantly (FDR)") +
  theme_classic(base_size = 12) +
  theme(legend.position = "none",
        plot.subtitle   = element_text(size = 9, color = "grey40"))
if (!is.null(cld_df)) {
  p_emm_facet <- p_emm_facet +
    geom_text(data = cld_df,
              aes(x = factor(BinCenter), y = asymp.UCL, label = .group),
              vjust = -0.5, size = 3.5, inherit.aes = FALSE)
}
ggsave(file.path(output_dir, "emm_barplot_per_condition.png"),
       p_emm_facet, width = 10, height = 4, dpi = 300)

p_emm_grouped <- ggplot(emm_df, aes(x = factor(BinCenter), y = prob,
                                     fill = Condition)) +
  geom_bar(stat = "identity", position = position_dodge(width = 0.8),
           width = 0.7, alpha = 0.85) +
  geom_errorbar(aes(ymin = asymp.LCL, ymax = asymp.UCL),
                position = position_dodge(width = 0.8),
                width = 0.25, linewidth = 0.5) +
  scale_fill_manual(values = colors, labels = cond_labels, name = "Condition") +
  scale_y_continuous(expand = expansion(mult = c(0.02, 0.2))) +
  labs(x = "Time from trial onset (s)",
       y = "Estimated Spindle Probability",
       title = "Model Estimates: Spindle Probability by Condition and Time Bin") +
  theme_classic(base_size = 12) +
  theme(legend.position = "right",
        legend.title    = element_text(face = "bold"))
if (nrow(sig_pairs) > 0) {
  p_emm_grouped <- p_emm_grouped +
    geom_segment(data = sig_pairs,
                 aes(x = x_start, xend = x_end,
                     y = y_bracket, yend = y_bracket),
                 inherit.aes = FALSE, linewidth = 0.3) +
    geom_segment(data = sig_pairs,
                 aes(x = x_start, xend = x_start,
                     y = y_bracket - bracket_step * 0.3,
                     yend = y_bracket),
                 inherit.aes = FALSE, linewidth = 0.3) +
    geom_segment(data = sig_pairs,
                 aes(x = x_end, xend = x_end,
                     y = y_bracket - bracket_step * 0.3,
                     yend = y_bracket),
                 inherit.aes = FALSE, linewidth = 0.3) +
    geom_text(data = sig_pairs,
              aes(x = (x_start + x_end) / 2, y = y_bracket, label = stars),
              inherit.aes = FALSE, vjust = -0.3, size = 3.5)
}
ggsave(file.path(output_dir, "emm_barplot_grouped.png"),
       p_emm_grouped, width = 8, height = 5, dpi = 300)

p3 <- ggplot(pred_data, aes(x = x, y = predicted, color = group, group = group)) +
  geom_line(size = 1.2) + geom_point(size = 3) +
  geom_errorbar(aes(ymin = conf.low, ymax = conf.high),
                width = 0.2, size = 0.8) +
  scale_color_manual(values = colors, labels = cond_labels, name = "Condition") +
  labs(x = "Time Bin", y = "Predicted Spindle Probability",
       title = "Model Predictions: Spindle Occurrence by Condition and Time") +
  theme_classic(base_size = 13) +
  theme(legend.position = "right",
        legend.title    = element_text(face = "bold"),
        plot.title      = element_text(face = "bold", size = 14))
ggsave(file.path(output_dir, "model_predictions_with_CI.png"),
       p3, width = 8, height = 5, dpi = 300)


# --- Exports ---

# Handoff CSVs consumed by figure3_M0_barplot.m. Column order: x5HZ, x1HZ, OFF.
subj_m0_wide <- subj_m0 %>%
  tidyr::pivot_wider(names_from = Condition, values_from = MeanProp) %>%
  select(Subject, x5HZ, x1HZ, OFF)
write.csv(subj_m0_wide,
          file.path(output_dir, "M0_barplot_subject_data.csv"),
          row.names = FALSE)
write.csv(subj_m0_summary,
          file.path(output_dir, "M0_barplot_summary.csv"),
          row.names = FALSE)

posthoc_export          <- emm_m0_pairs_df
posthoc_export$contrast <- as.character(posthoc_export$contrast)
posthoc_export$cond1    <- trimws(sub(" [-/] .*", "", posthoc_export$contrast))
posthoc_export$cond2    <- trimws(sub(".* [-/] ",  "", posthoc_export$contrast))
write.csv(posthoc_export,
          file.path(output_dir, "M0_barplot_posthoc.csv"),
          row.names = FALSE)

writeLines(sprintf("%.10g", m0_cond_p),
           file.path(output_dir, "M0_barplot_omnibus_p.txt"))

# Main statistical report. Several strings here are parsed by
# figure3_emmFromTextReport.m and MUST be preserved verbatim:
#   "*** Best model: <name> (AIC: ...)"
#   "Time Bins: <n> (<lo> to <hi> s)"
#   "GLMM: <name>"      (at the start of a line)
#   "Estimated Marginal Means (Probability Scale):"
#   "Post-hoc Contrasts: Conditions within Time Bins:"
#   "Post-hoc Contrasts: Time Bins within Conditions:"
sink(file.path(output_dir, "GLMM_statistical_results.txt"))

cat("GLMM Statistical Analysis -- Temporal Distribution of Spindles\n")
cat(sprintf("Analysis Date: %s\n\n", Sys.Date()))
cat(sprintf("Subjects: %d\n",  length(unique(dat$Subject))))
cat(sprintf("Conditions: %s\n", paste(levels(dat$Condition), collapse = ", ")))
cat(sprintf("Time Bins: %d (%.2f to %.2f s)\n",
            length(unique(dat$BinCenter)),
            min(dat$BinCenter), max(dat$BinCenter)))
cat(sprintf("Observations: %d, spindles: %d (%.2f%%)\n\n",
            nrow(dat), sum(dat$Spindle), 100 * mean(dat$Spindle)))

cat("Spindle Probability by Condition (subject-level means)\n")
desc_by_cond <- dat %>%
  group_by(Subject, Condition) %>%
  summarise(SubjProp = mean(Spindle), .groups = "drop") %>%
  group_by(Condition) %>%
  summarise(N_subjects = n(),
            Mean_Prob = mean(SubjProp), SD_Prob = sd(SubjProp),
            Min_Prob  = min(SubjProp),  Max_Prob = max(SubjProp),
            .groups = "drop")
cat(sprintf("  %-10s  N   Mean       SD         Min        Max\n", "Condition"))
cat(sprintf("  %s\n", paste(rep("-", 65), collapse = "")))
for (i in seq_len(nrow(desc_by_cond))) {
  cat(sprintf("  %-10s %2d   %.6f   %.6f   %.6f   %.6f\n",
              desc_by_cond$Condition[i], desc_by_cond$N_subjects[i],
              desc_by_cond$Mean_Prob[i], desc_by_cond$SD_Prob[i],
              desc_by_cond$Min_Prob[i],  desc_by_cond$Max_Prob[i]))
}

cat("\n\nSpindle Probability by Condition x Time Bin\n")
desc_by_cond_bin <- dat %>%
  group_by(Subject, Condition, TimeBin, BinCenter) %>%
  summarise(SubjProp = mean(Spindle), .groups = "drop") %>%
  group_by(Condition, TimeBin, BinCenter) %>%
  summarise(N_subjects = n(),
            Mean_Prob = mean(SubjProp), SD_Prob = sd(SubjProp),
            .groups = "drop")
cat(sprintf("  %-10s  %-8s  %8s  N   Mean       SD\n",
            "Condition", "TimeBin", "Center"))
cat(sprintf("  %s\n", paste(rep("-", 60), collapse = "")))
for (i in seq_len(nrow(desc_by_cond_bin))) {
  cat(sprintf("  %-10s  %-8s  %7.2f  %2d   %.6f   %.6f\n",
              desc_by_cond_bin$Condition[i], desc_by_cond_bin$TimeBin[i],
              desc_by_cond_bin$BinCenter[i], desc_by_cond_bin$N_subjects[i],
              desc_by_cond_bin$Mean_Prob[i], desc_by_cond_bin$SD_Prob[i]))
}

cat("\n\nModel Comparison\n")
print(comparison)
cat(sprintf("\n*** Best model: %s (AIC: %.2f, BIC: %.2f) ***\n",
            best_model_name, AIC(best_model), BIC(best_model)))

for (mname in names(glmm_model_results)) {
  res <- glmm_model_results[[mname]]
  cat(sprintf("\n\nGLMM: %s\n", mname))
  cat("Formula: "); print(res$formula)
  cat(sprintf("AIC: %.2f  |  BIC: %.2f\n\n", res$aic, res$bic))
  cat("Fixed Effects:\n"); print(res$summary_obj$coefficients, digits = 4)
  cat("\nRandom Effects:\n"); print(res$varcorr)
  if (!is.null(res$anova_III)) {
    cat("\nType III Wald Tests:\n"); print(res$anova_III)
  }
  if (!is.null(res$emm_data)) {
    cat("\nEstimated Marginal Means (Probability Scale):\n")
    print(res$emm_data$emm_summary)
    if (mname == "M0: Condition only") {
      cat("\nPost-hoc Pairwise Condition Comparisons:\n")
      print(res$emm_data$contrast_cond)
    } else {
      cat("\nPost-hoc Contrasts: Conditions within Time Bins:\n")
      print(res$emm_data$contrast_cond)
      cat("\nPost-hoc Contrasts: Time Bins within Conditions:\n")
      print(res$emm_data$contrast_bin)
    }
  }
}

cat("\n\nEffect Sizes -- Odds Ratios (best model)\n")
print(effect_sizes, digits = 3)

for (lmm_name in names(lmm_model_results)) {
  res <- lmm_model_results[[lmm_name]]
  cat(sprintf("\n\nLMM: %s\n", lmm_name))
  cat("Formula: "); print(res$formula)
  cat(sprintf("AIC: %.2f  |  BIC: %.2f\n\n", res$aic, res$bic))
  print(res$summary_obj)
  if (!is.null(res$anova_III)) {
    cat("\nType III Tests (Kenward-Roger):\n"); print(res$anova_III)
  }
  if (!is.null(res$emm_data)) {
    cat("\nPost-hoc Contrasts: Conditions within Time Bins:\n")
    print(res$emm_data$contrast_cond)
  }
}

cat("\n\nSensitivity: Subject-level Model\n")
print(lmm_subj_summary)
cat("\nType III Tests:\n"); print(lmm_subj_anova)

cat("\n\nModel Diagnostics (DHARMa) -- ", best_model_name, "\n", sep = "")
diag_tests <- list(
  list(name = "Uniformity (KS test)",  test = uniformity_test),
  list(name = "Dispersion",             test = dispersion_test),
  list(name = "Zero-inflation",         test = zeroinflation_test),
  list(name = "Outlier test (boot)",    test = outlier_test)
)
for (dt in diag_tests) {
  outcome <- if (dt$test$p.value >= 0.05) "PASS" else "FAIL"
  cat(sprintf("  %-30s stat = %.4f, p = %.4f, %s\n",
              dt$name, dt$test$statistic, dt$test$p.value, outcome))
}
n_pass <- sum(sapply(diag_tests, function(dt) dt$test$p.value >= 0.05))
cat(sprintf("  %d/4 diagnostics passed (alpha = 0.05)\n", n_pass))

cat("\n\nProfile-likelihood CIs for condition contrasts by time bin\n")
print(contrast_boot_ci)

cat("\n\nObserved Effect Sizes per Time Bin\n")
print(power_analysis, digits = 3)

sink()


# RData snapshot of fitted models and key summaries.
save(best_model, m0, m1, m2, m3, m4, m5,
     best_lmm, lmm1, lmm2, lmm3, lmm_subj,
     emm, contrast_cond_by_bin_summary, contrast_bin_by_cond_summary,
     effect_sizes, power_analysis, desc_stats, subj_stats,
     file = file.path(output_dir, "GLMM_models_and_results.RData"))

# Per-model EMM / contrast CSVs.
write.csv(desc_stats,
          file.path(output_dir, "descriptive_statistics.csv"),
          row.names = FALSE)
write.csv(effect_sizes,
          file.path(output_dir, "effect_sizes_odds_ratios.csv"),
          row.names = FALSE)

safe_label <- function(name) {
  out <- gsub("[^A-Za-z0-9]", "_", name)
  out <- gsub("_+", "_", out)
  gsub("^_|_$", "", out)
}

for (mname in names(glmm_model_results)) {
  res     <- glmm_model_results[[mname]]
  m_label <- safe_label(mname)
  if (is.null(res$emm_data)) next
  write.csv(as.data.frame(res$emm_data$emm_summary),
            file.path(output_dir, sprintf("emm_%s.csv", m_label)),
            row.names = FALSE)
  write.csv(as.data.frame(res$emm_data$contrast_cond),
            file.path(output_dir,
                      sprintf("contrasts_condition_by_timebin_%s.csv", m_label)),
            row.names = FALSE)
  if (!is.null(res$emm_data$contrast_bin)) {
    write.csv(as.data.frame(res$emm_data$contrast_bin),
              file.path(output_dir,
                        sprintf("contrasts_timebin_by_condition_%s.csv", m_label)),
              row.names = FALSE)
  }
}

for (lmm_name in names(lmm_model_results)) {
  res     <- lmm_model_results[[lmm_name]]
  l_label <- safe_label(lmm_name)
  if (is.null(res$emm_data)) next
  write.csv(as.data.frame(res$emm_data$emm_summary),
            file.path(output_dir, sprintf("emm_%s.csv", l_label)),
            row.names = FALSE)
  write.csv(as.data.frame(res$emm_data$contrast_cond),
            file.path(output_dir,
                      sprintf("contrasts_condition_by_timebin_%s.csv", l_label)),
            row.names = FALSE)
}

# Supplementary tables (S1--S6) for the manuscript.
suppl_file <- file.path(output_dir,
                         "supplementary_tables_GLMM_spindle_probability.txt")
sink(suppl_file)

cat("Supplementary Tables: Spindle Probability GLMM Analysis\n")
cat(sprintf("Generated: %s\n\n", Sys.time()))
cat("Binary spindle occurrence (0/1) per subject x electrode x trial x time-bin\n")
cat("observation, modelled with binomial-logit GLMMs (lme4::glmer, ML, Laplace).\n\n")

cat("TABLE S1. Spindle Probability by Condition\n\n")
desc_s1 <- dat %>%
  group_by(Subject, Condition) %>%
  summarise(SubjProp = mean(Spindle), .groups = "drop") %>%
  group_by(Condition) %>%
  summarise(N = n(),
            Mean = mean(SubjProp), SD = sd(SubjProp),
            Min  = min(SubjProp),  Max = max(SubjProp),
            .groups = "drop")
cat(sprintf("%-12s %4s %10s %10s %10s %10s\n",
            "Condition", "N", "Mean", "SD", "Min", "Max"))
cat(sprintf("%s\n", paste(rep("-", 60), collapse = "")))
for (i in seq_len(nrow(desc_s1))) {
  cat(sprintf("%-12s %4d %10.6f %10.6f %10.6f %10.6f\n",
              as.character(desc_s1$Condition[i]), desc_s1$N[i],
              desc_s1$Mean[i], desc_s1$SD[i],
              desc_s1$Min[i],  desc_s1$Max[i]))
}

cat("\n\nTABLE S2. Spindle Probability by Condition x Time Bin\n\n")
desc_s2 <- dat %>%
  group_by(Subject, Condition, TimeBin, BinCenter) %>%
  summarise(SubjProp = mean(Spindle), .groups = "drop") %>%
  group_by(Condition, TimeBin, BinCenter) %>%
  summarise(N = n(),
            Mean = mean(SubjProp), SD = sd(SubjProp),
            .groups = "drop")
cat(sprintf("%-10s %8s %8s %4s %10s %10s\n",
            "Condition", "TimeBin", "Bin (s)", "N", "Mean", "SD"))
cat(sprintf("%s\n", paste(rep("-", 55), collapse = "")))
for (i in seq_len(nrow(desc_s2))) {
  cat(sprintf("%-10s %8s %8.2f %4d %10.6f %10.6f\n",
              as.character(desc_s2$Condition[i]),
              as.character(desc_s2$TimeBin[i]),
              desc_s2$BinCenter[i], desc_s2$N[i],
              desc_s2$Mean[i], desc_s2$SD[i]))
}

cat("\n\nTABLE S3. Model Comparison\n\n")
for (mname in names(model_list)) {
  cat(sprintf("%-25s  AIC = %10.2f  BIC = %10.2f\n",
              mname,
              AIC(model_list[[mname]]),
              BIC(model_list[[mname]])))
}
cat("\n"); print(comparison)
cat(sprintf("\nBest model: %s\n", best_model_name))

print_model_table <- function(mname, table_label) {
  res <- glmm_model_results[[mname]]
  cat(sprintf("\n\n%s\n\n", table_label))
  cat("Formula: "); print(res$formula)
  cat(sprintf("\nAIC = %.2f, BIC = %.2f\n", res$aic, res$bic))

  cat("\nFixed Effects\n")
  ct <- coef(res$summary_obj)
  cat(sprintf("%-30s %10s %10s %10s %12s\n",
              "Parameter", "Estimate", "SE", "z value", "p"))
  cat(sprintf("%s\n", paste(rep("-", 75), collapse = "")))
  for (j in seq_len(nrow(ct))) {
    pval <- ct[j, "Pr(>|z|)"]
    pstr <- if (pval < 0.001) "< .001" else sprintf("%.4f", pval)
    cat(sprintf("%-30s %10.4f %10.4f %10.3f %12s\n",
                rownames(ct)[j],
                ct[j, "Estimate"], ct[j, "Std. Error"],
                ct[j, "z value"],  pstr))
  }

  cat("\nRandom Effects\n"); print(res$varcorr)
  if (!is.null(res$anova_III)) {
    cat("\nType III Wald Chi-Square Tests\n"); print(res$anova_III)
  }
  if (!is.null(res$emm_data)) {
    cat("\nEstimated Marginal Means (probability scale)\n")
    print(res$emm_data$emm_summary)
    cat("\nPost-Hoc Pairwise Contrasts (FDR-corrected)\n")
    print(res$emm_data$contrast_cond)
    if (!is.null(res$emm_data$contrast_bin)) {
      cat("\nPost-Hoc Contrasts: Time Bins within Conditions (FDR-corrected)\n")
      print(res$emm_data$contrast_bin)
    }
  }
}

print_model_table("M0: Condition only",
                  "TABLE S4. Simple Model (M0) -- Condition Only")
print_model_table("M5: +Condition slope",
                  "TABLE S5. Best Model (M5) -- Condition x TimeBin with Random Slopes")

cat("\n\nTABLE S6. Model Diagnostics (DHARMa) -- Best Model\n\n")
cat(sprintf("%-30s %12s %10s %8s\n", "Test", "Statistic", "p value", "Result"))
cat(sprintf("%s\n", paste(rep("-", 65), collapse = "")))
for (dt in diag_tests) {
  outcome <- if (dt$test$p.value >= 0.05) "PASS" else "FAIL"
  cat(sprintf("%-30s %12.4f %10.4f %8s\n",
              dt$name, dt$test$statistic, dt$test$p.value, outcome))
}
cat(sprintf("\n%d/4 diagnostics passed (alpha = 0.05)\n", n_pass))

sink()

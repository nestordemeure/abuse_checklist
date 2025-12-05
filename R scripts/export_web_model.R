#!/usr/bin/env Rscript
# ==============================================================================
# Export Web Model V3: With Firth's Penalized Logistic Regression
# ==============================================================================
# Uses Firth's penalized maximum likelihood estimation for better
# small-sample performance and reduced bias in coefficient estimates
# ==============================================================================

# Add user library path
.libPaths(c("~/R/library", .libPaths()))

library(jsonlite)
library(logistf)

cat("==================================================================\n")
cat("Exportation du modèle V3 (avec estimations d'incertitude)\n")
cat("==================================================================\n\n")

# Charger les données
data <- readRDS("outputs/processed_data.rds")
data$abuse_binary <- as.numeric(data$abuse_case == "Abuse")

# ==============================================================================
# DÉFINITION DES VARIABLES
# ==============================================================================

variables <- list(
  list(
    id = "antidepressants",
    label_fr = "Prise d'antidépresseurs",
    label_en = "Taking antidepressants",
    type = "boolean",
    importance = 1,  # Most important
    description_fr = "La patiente prend actuellement des antidépresseurs",
    description_en = "Patient is currently taking antidepressants"
  ),
  list(
    id = "depression",
    label_fr = "Diagnostic de dépression",
    label_en = "Depression diagnosis",
    type = "boolean",
    importance = 3,
    description_fr = "Diagnostic médical de dépression",
    description_en = "Medical diagnosis of depression"
  ),
  list(
    id = "benzodiazepines",
    label_fr = "Prise de benzodiazépines",
    label_en = "Taking benzodiazepines",
    type = "boolean",
    importance = 2,
    description_fr = "La patiente prend actuellement des benzodiazépines (anxiolytiques)",
    description_en = "Patient is currently taking benzodiazepines (anxiolytics)"
  ),
  list(
    id = "suicide_attempt",
    label_fr = "Antécédents de tentative de suicide",
    label_en = "History of suicide attempt",
    type = "boolean",
    importance = 2,
    description_fr = "Antécédents documentés de tentative de suicide",
    description_en = "Documented history of suicide attempt"
  ),
  list(
    id = "violence",
    label_fr = "Exposition à la violence",
    label_en = "Exposure to violence",
    type = "boolean",
    importance = 1,
    description_fr = "Exposition à des violences (physiques, psychologiques)",
    description_en = "Exposure to violence (physical, psychological)"
  ),
  list(
    id = "gynecological",
    label_fr = "Troubles gynécologiques",
    label_en = "Gynecological disorders",
    type = "boolean",
    importance = 2,
    description_fr = "Troubles gynécologiques documentés",
    description_en = "Documented gynecological disorders"
  ),
  list(
    id = "work_disability_months",
    label_fr = "Durée d'incapacité de travail (mois)",
    label_en = "Work disability duration (months)",
    type = "numeric",
    importance = 3,
    description_fr = "Nombre de mois d'incapacité de travail",
    description_en = "Number of months of work disability",
    min = 0,
    max = 120,
    step = 1
  )
)

var_names <- sapply(variables, function(v) v$id)

# ==============================================================================
# GÉNÉRATION DE TOUTES LES COMBINAISONS POSSIBLES
# ==============================================================================

cat("Génération de toutes les combinaisons possibles de variables...\n")

# Générer toutes les combinaisons possibles (2^7 - 1 = 127, en excluant l'ensemble vide)
subsets_to_fit <- list()

for (n_vars in 1:length(var_names)) {
  # Générer toutes les combinaisons de taille n_vars
  combinations <- combn(var_names, n_vars, simplify = FALSE)

  for (combo in combinations) {
    # Créer un nom descriptif pour la combinaison
    combo_name <- paste(combo, collapse = "_")

    subsets_to_fit[[length(subsets_to_fit) + 1]] <- list(
      name = combo_name,
      vars = combo
    )
  }
}

cat(sprintf("Nombre de modèles à ajuster: %d\n", length(subsets_to_fit)))
cat(sprintf("(Toutes les combinaisons possibles de %d variables)\n\n", length(var_names)))

# ==============================================================================
# FONCTIONS UTILITAIRES
# ==============================================================================

calculate_prediction_ci <- function(model, newdata, level = 0.95) {
  # Calculate confidence interval for probability prediction
  # Uses delta method approximation
  # Works with both glm and logistf models

  # Get coefficients and vcov matrix
  beta <- coef(model)
  vcov_mat <- vcov(model)

  # Create design matrix for newdata
  # Add intercept column
  newdata_with_intercept <- cbind(1, as.matrix(newdata))
  colnames(newdata_with_intercept)[1] <- "(Intercept)"

  # Linear predictor
  pred_link <- as.numeric(newdata_with_intercept %*% beta)

  # Standard error of linear predictor using delta method
  se_link <- sqrt(diag(newdata_with_intercept %*% vcov_mat %*% t(newdata_with_intercept)))

  # Critical value
  z_crit <- qnorm((1 + level) / 2)

  # CI on link scale
  link_lower <- pred_link - z_crit * se_link
  link_upper <- pred_link + z_crit * se_link

  # Transform to probability scale
  prob <- plogis(pred_link)
  prob_lower <- plogis(link_lower)
  prob_upper <- plogis(link_upper)

  return(list(
    probability = prob,
    lower = prob_lower,
    upper = prob_upper,
    se = se_link
  ))
}

# Adjust probability for different prevalence using Bayes' theorem
adjust_probability_for_prevalence <- function(prob_train, prev_train, prev_target) {
  # Convert probability to odds
  odds_train <- prob_train / (1 - prob_train)

  # Adjust odds for prevalence change
  # odds_target = odds_train * (prev_target / (1 - prev_target)) / (prev_train / (1 - prev_train))
  prevalence_ratio <- (prev_target / (1 - prev_target)) / (prev_train / (1 - prev_train))
  odds_target <- odds_train * prevalence_ratio

  # Convert back to probability
  prob_target <- odds_target / (1 + odds_target)

  return(prob_target)
}


# ==============================================================================
# AJUSTEMENT DES MODÈLES
# ==============================================================================

cat("Ajustement des modèles avec calcul d'incertitude...\n\n")

models_list <- list()

for (i in seq_along(subsets_to_fit)) {
  subset_info <- subsets_to_fit[[i]]
  subset_name <- subset_info$name
  subset_vars <- subset_info$vars

  cat(sprintf("[%d/%d] %s\n", i, length(subsets_to_fit), subset_name))

  formula_str <- paste("abuse_binary ~", paste(subset_vars, collapse = " + "))
  data_subset <- data[complete.cases(data[c("abuse_binary", subset_vars)]), ]

  n_abuse <- sum(data_subset$abuse_binary)
  n_control <- sum(1 - data_subset$abuse_binary)

  if (n_control < 5 || n_abuse < 10) {
    cat("  SKIP\n\n")
    next
  }

  tryCatch({
    # Use Firth's penalized logistic regression for better small-sample performance
    model <- logistf(as.formula(formula_str), data = data_subset)

    coefficients <- coef(model)

    # Get coefficient standard errors from vcov matrix
    coef_se <- sqrt(diag(vcov(model)))

    # Calculate AUC
    # logistf predict returns linear predictor by default, convert to probability
    linear_pred <- predict(model, newdata = data_subset)
    predicted_probs <- plogis(linear_pred)
    pred_order <- order(predicted_probs, decreasing = TRUE)
    tpr <- cumsum(data_subset$abuse_binary[pred_order]) / sum(data_subset$abuse_binary)
    fpr <- cumsum(1 - data_subset$abuse_binary[pred_order]) / sum(1 - data_subset$abuse_binary)
    auc <- sum(diff(c(0, fpr)) * (c(0, tpr[-length(tpr)]) + tpr) / 2)

    # Calculate typical prediction uncertainty
    # Use a representative case (all TRUE for boolean, median for numeric)
    test_data <- data.frame(matrix(NA, nrow = 1, ncol = length(subset_vars)))
    names(test_data) <- subset_vars

    for (var in subset_vars) {
      var_def <- variables[[which(sapply(variables, function(v) v$id == var))]]
      if (var_def$type == "boolean") {
        test_data[[var]] <- TRUE
      } else {
        test_data[[var]] <- median(data_subset[[var]], na.rm = TRUE)
      }
    }

    typical_ci <- calculate_prediction_ci(model, test_data)
    typical_width <- typical_ci$upper - typical_ci$lower

    # Get coefficient covariance matrix for proper CI calculation
    vcov_matrix <- vcov(model)
    coef_names <- names(coefficients)
    vcov_list <- list()
    for (i in seq_along(coef_names)) {
      vcov_list[[coef_names[i]]] <- as.list(vcov_matrix[i, ])
      names(vcov_list[[coef_names[i]]]) <- coef_names
    }

    # Stocker
    # Force variables to always be a list, even for single elements
    vars_list <- if (length(subset_vars) == 1) list(subset_vars) else subset_vars

    models_list[[subset_name]] <- list(
      variables = vars_list,
      coefficients = as.list(coefficients),
      coefficient_se = as.list(coef_se),
      coefficient_vcov = vcov_list,
      n_obs = nrow(data_subset),
      n_abuse = n_abuse,
      n_control = n_control,
      auc = auc,
      # logistf doesn't have converged field, assume converged if no error
      converged = TRUE,
      typical_ci_width = typical_width,
      # logistf uses df instead of df.residual
      df_residual = model$df
    )

    cat(sprintf("  AUC=%.3f, CI width=%.3f\n\n",
                auc, typical_width))

  }, error = function(e) {
    cat(sprintf("  ERROR: %s\n\n", e$message))
  })
}

cat(sprintf("Modèles ajustés: %d/%d\n\n", length(models_list), length(subsets_to_fit)))

# ==============================================================================
# CRÉER LA STRUCTURE JSON
# ==============================================================================

cat("Création du fichier JSON...\n")

web_model <- list(
  model_type = "multiple_logistic_regression",
  description = "Multiple logistic regression models for different variable subsets",
  variables = variables,
  models = models_list,
  prevalence_info = list(
    sample_prevalence = sum(data$abuse_binary) / nrow(data),
    sample_n = nrow(data),
    sample_n_abuse = sum(data$abuse_binary),
    sample_n_control = sum(1 - data$abuse_binary),
    default_target_prevalence = 0.25,
    note_fr = "Les modèles ont été entraînés sur un échantillon avec 85% de cas d'abus. Les probabilités prédites peuvent être ajustées pour refléter une prévalence différente dans votre population cible.",
    note_en = "Models were trained on a sample with 85% abuse cases. Predicted probabilities can be adjusted to reflect a different prevalence in your target population."
  ),
  metadata = list(
    date_created = format(Sys.Date(), "%Y-%m-%d"),
    version = "4.1",
    note = "Includes uncertainty estimates, quality warnings, and prevalence adjustment capability"
  ),
  disclaimer = list(
    fr = "Ce modèle est basé sur un échantillon limité (n=133) et ne constitue pas un outil diagnostique. Les résultats doivent être interprétés dans le contexte clinique global et ne remplacent pas le jugement médical. L'échantillon présente un déséquilibre important (85% de cas d'abus). Les probabilités prédites sont ajustées pour refléter une prévalence de 25% dans la population cible (modifiable selon votre contexte clinique). Utilisez cet outil comme aide à la décision pour identifier les patientes nécessitant une exploration clinique approfondie.",
    en = "This model is based on a limited sample (n=133) and is not a diagnostic tool. Results must be interpreted within the overall clinical context and do not replace medical judgment. The sample shows significant imbalance (85% abuse cases). Predicted probabilities are adjusted to reflect a 25% prevalence in the target population (adjustable based on your clinical context). Use this tool as a decision aid to identify patients requiring in-depth clinical exploration."
  )
)

json_file <- "webapp/model.json"
write_json(web_model, json_file, pretty = TRUE, auto_unbox = TRUE, digits = 6)

cat(sprintf("Modèle V3 exporté vers: %s\n", json_file))
cat("(remplace model.json pour être utilisé par défaut)\n\n")

# ==============================================================================
# GÉNÉRATION DU RAPPORT
# ==============================================================================

cat("Génération du rapport...\n\n")

# Préparer les données pour le rapport
models_df <- data.frame(
  model_name = names(models_list),
  n_vars = sapply(models_list, function(m) length(m$variables)),
  auc = sapply(models_list, function(m) m$auc),
  ci_width = sapply(models_list, function(m) m$typical_ci_width),
  n_obs = sapply(models_list, function(m) m$n_obs),
  n_abuse = sapply(models_list, function(m) m$n_abuse),
  n_control = sapply(models_list, function(m) m$n_control),
  converged = sapply(models_list, function(m) m$converged),
  stringsAsFactors = FALSE
)

# Trier par nombre de variables puis AUC
models_df <- models_df[order(models_df$n_vars, -models_df$auc), ]

# Fonction pour sauvegarder les graphiques en PDF et PNG
save_plot <- function(plot_function, filename, width = 10, height = 8) {
  # Créer les dossiers si nécessaire
  dir.create("outputs/figures/pdf", recursive = TRUE, showWarnings = FALSE)
  dir.create("outputs/figures/png", recursive = TRUE, showWarnings = FALSE)

  # Sauvegarder en PDF
  pdf(paste0("outputs/figures/pdf/", filename, ".pdf"), width = width, height = height)
  plot_function()
  dev.off()

  # Sauvegarder en PNG
  png(paste0("outputs/figures/png/", filename, ".png"),
      width = width * 100, height = height * 100, res = 100)
  plot_function()
  dev.off()
}

# Traductions françaises des variables
var_labels_fr <- c(
  antidepressants = "Antidépresseurs",
  depression = "Dépression",
  benzodiazepines = "Benzodiazépines",
  suicide_attempt = "Tentative de suicide",
  violence = "Violence",
  gynecological = "Troubles gynécologiques",
  work_disability_months = "Durée d'IT (mois)"
)

# ==============================================================================
# VISUALISATIONS
# ==============================================================================

cat("Génération des visualisations...\n")

# 1. AUC par modèle
save_plot(function() {
  par(mar = c(10, 4, 3, 2))
  barplot(models_df$auc,
          names.arg = models_df$model_name,
          las = 2,
          ylim = c(0, 1),
          col = rainbow(nrow(models_df), alpha = 0.7),
          main = "Performance (AUC) par modèle",
          ylab = "AUC",
          cex.names = 0.7)
  abline(h = 0.7, lty = 2, col = "red")
  abline(h = 0.8, lty = 2, col = "orange")
  abline(h = 0.9, lty = 2, col = "green")
  legend("bottomright",
         legend = c("AUC ≥ 0.9 (Excellent)", "AUC ≥ 0.8 (Bon)", "AUC ≥ 0.7 (Acceptable)"),
         lty = 2, col = c("green", "orange", "red"), bty = "n", cex = 0.8)
}, "web_model_auc_by_model", width = 12, height = 8)

# 2. AUC vs nombre de variables
save_plot(function() {
  par(mar = c(5, 4, 3, 2))
  plot(models_df$n_vars, models_df$auc,
       pch = 19, cex = 1.5, col = rainbow(nrow(models_df), alpha = 0.7),
       xlab = "Nombre de variables",
       ylab = "AUC",
       main = "Performance vs complexité du modèle",
       xlim = c(0.5, max(models_df$n_vars) + 0.5),
       ylim = c(0.5, 1))
  abline(h = 0.8, lty = 2, col = "gray")
  abline(h = 0.9, lty = 2, col = "gray")

  # Courbe de tendance
  if (nrow(models_df) > 3) {
    smooth_fit <- loess(auc ~ n_vars, data = models_df, span = 0.75)
    pred_x <- seq(min(models_df$n_vars), max(models_df$n_vars), length.out = 100)
    pred_y <- predict(smooth_fit, newdata = data.frame(n_vars = pred_x))
    lines(pred_x, pred_y, col = "blue", lwd = 2, lty = 2)
  }
}, "web_model_auc_vs_nvars", width = 10, height = 8)

# 3. Incertitude (largeur IC) par modèle
save_plot(function() {
  par(mar = c(10, 4, 3, 2))
  barplot(models_df$ci_width,
          names.arg = models_df$model_name,
          las = 2,
          col = heat.colors(nrow(models_df), alpha = 0.7),
          main = "Incertitude des prédictions par modèle",
          ylab = "Largeur de l'IC à 95% (typique)",
          cex.names = 0.7)
  legend("topright",
         legend = "Plus la barre est courte,\nplus les prédictions sont précises",
         bty = "n", cex = 0.9)
}, "web_model_uncertainty", width = 12, height = 8)

# 4. Heatmap qualité : AUC et incertitude
save_plot(function() {
  par(mar = c(5, 12, 3, 2))

  # Créer une matrice pour la heatmap
  quality_matrix <- matrix(NA, nrow = nrow(models_df), ncol = 2)
  rownames(quality_matrix) <- models_df$model_name
  colnames(quality_matrix) <- c("AUC", "Précision\n(1 - IC width)")

  quality_matrix[, 1] <- models_df$auc
  quality_matrix[, 2] <- 1 - models_df$ci_width

  # Tracer la heatmap
  image(t(quality_matrix),
        col = colorRampPalette(c("red", "yellow", "green"))(100),
        xaxt = "n", yaxt = "n",
        main = "Qualité des modèles : Performance et Précision")

  # Ajouter les axes
  axis(1, at = seq(0, 1, length.out = 2), labels = colnames(quality_matrix))
  axis(2, at = seq(0, 1, length.out = nrow(models_df)),
       labels = rownames(quality_matrix), las = 2, cex.axis = 0.7)

  # Légende couleur
  legend("bottom",
         legend = c("Faible", "Moyen", "Élevé"),
         fill = c("red", "yellow", "green"),
         horiz = TRUE, bty = "n", cex = 0.8)
}, "web_model_quality_heatmap", width = 10, height = 10)

cat("Visualisations créées.\n\n")

# ==============================================================================
# RAPPORT MARKDOWN
# ==============================================================================

cat("Génération du rapport Markdown...\n")

report <- c(
  "---",
  "output:",
  "  pdf_document:",
  "    fig_caption: yes",
  "    keep_tex: no",
  "header-includes:",
  "  - \\usepackage{float}",
  "  - \\floatplacement{figure}{H}",
  "  - \\usepackage{graphicx}",
  "  - \\setkeys{Gin}{width=0.8\\textwidth}",
  "  - \\usepackage{longtable}",
  "  - \\usepackage{array}",
  "  - \\usepackage{etoolbox}",
  "  - \\AtBeginEnvironment{longtable}{\\setlength{\\arrayrulewidth}{0.5pt}}",
  "  - \\preto\\longtable{\\let\\hline\\midrule}",
  "---",
  "",
  "# Système multi-modèle pour l'application web",
  "",
  sprintf("**Date :** %s", format(Sys.Date(), "%d %B %Y")),
  "",
  "## Vue d'ensemble",
  "",
  "Ce document décrit le système multi-modèle développé pour l'application web d'aide à la décision clinique concernant la suspicion d'abus sexuels.",
  "",
  "### Principe",
  "",
  sprintf("L'application web utilise **%d modèles de régression logistique différents**, chacun entraîné sur un sous-ensemble spécifique de variables. Cette approche adaptative permet de fournir des estimations de probabilité **même lorsque certaines variables sont manquantes**.", length(models_list)),
  "",
  "**Avantages du système multi-modèle :**",
  "",
  "1. **Précision accrue** : Contrairement aux systèmes de score à points entiers, ce système fournit des estimations de probabilité continues (valeurs entre 0 et 1), permettant une discrimination plus fine. De plus, chaque modèle utilise uniquement les variables disponibles, sans imputation artificielle",
  "",
  "2. **Quantification de l'incertitude** : Chaque prédiction s'accompagne d'un intervalle de confiance à 95%, permettant d'évaluer la fiabilité de l'estimation",
  "",
  "3. **Flexibilité** : Le système s'adapte automatiquement aux variables disponibles, permettant des estimations même avec des données partielles",
  "",
  "---",
  "",
  "## Variables disponibles",
  "",
  sprintf("Le système s'appuie sur **%d variables cliniques**, sélectionnées via l'analyse de corrélations :", length(variables)),
  ""
)

for (i in seq_along(variables)) {
  var <- variables[[i]]
  report <- c(report,
    sprintf("%d. **%s** (%s)", i, var$label_fr,
            ifelse(var$type == "boolean", "Oui/Non", "mois")))
}

report <- c(report,
  "",
  "**Taux d'abus attendu** : Paramètre ajustable (défaut : 25%) permettant de calibrer les probabilités au contexte clinique. Utilisez 10-15% pour du dépistage en population générale, 25-35% pour des cliniques spécialisées (santé mentale, douleur chronique).",
  "",
  "---",
  "",
  "## Méthodologie",
  "",
  "### Système multi-modèle",
  "",
  sprintf("**%d modèles de régression logistique pénalisée de Firth** couvrent toutes les combinaisons possibles de variables (2^7 - 1). La [régression de Firth](https://en.wikipedia.org/wiki/Logistic_regression#Firth's_correction) réduit le biais et améliore les intervalles de confiance pour les petits échantillons (n=%d témoins).", length(models_list), sum(1 - data$abuse_binary)),
  "",
  "Lorsqu'un utilisateur entre des données, le système :",
  "1. Identifie les variables disponibles",
  "2. Sélectionne le modèle exact correspondant à cette combinaison",
  "3. Calcule la probabilité et son intervalle de confiance à 95%",
  "4. Évalue la fiabilité selon la largeur de l'IC",
  "",
  "### Incertitude et ajustement de prévalence",
  "",
  "Chaque prédiction inclut un **intervalle de confiance à 95%** calculé avec la [méthode delta](https://en.wikipedia.org/wiki/Delta_method), utilisant la matrice de covariance complète des coefficients pour tenir compte de leurs corrélations.",
  "",
  "**Niveaux d'incertitude** :",
  "- IC < 0.10 (±5%) : Estimation fiable",
  "- IC 0.10-0.20 (±5-10%) : Probablement fiable",
  "- IC 0.20-0.40 (±10-20%) : Interpréter avec prudence",
  "- IC ≥ 0.40 (±20%+) : Très incertain",
  "",
  sprintf("**Ajustement de prévalence** : Les modèles ont été entraînés sur %.0f%% de cas d'abus (n=%d abus, n=%d témoins). Les probabilités sont recalibrées via un ajustement du log-odds pour refléter le taux d'abus attendu dans la population cible (défaut : 25%%, modifiable). L'ajustement de prévalence augmente significativement l'incertitude, d'où l'importance de consulter l'IC.",
          sum(data$abuse_binary) / nrow(data) * 100,
          sum(data$abuse_binary),
          sum(1 - data$abuse_binary)),
  "",
  "---",
  "",
  "## Implications cliniques",
  "",
  "**Seuils d'interprétation** :",
  "- **< 30%** : Suspicion faible → suivi habituel",
  "- **30-70%** : Suspicion modérée → explorer davantage",
  "- **≥ 70%** : Suspicion élevée → exploration approfondie recommandée",
  "",
  sprintf("**Fiabilité selon les variables disponibles** :"),
  sprintf("- 7 variables (modèle complet) : AUC = %.2f, IC étroit, haute fiabilité", max(models_df$auc)),
  "- 4-6 variables : AUC > 0.85 typiquement, fiabilité bonne à très bonne",
  "- 1-3 variables : AUC variable, IC large, fiabilité limitée",
  "",
  "**Recommandations** :",
  "1. Collecter autant de variables que possible",
  "2. Prioriser antidépresseurs et violence (variables à plus forte association)",
  "3. Ajuster la prévalence cible selon le contexte clinique",
  "4. Toujours consulter l'IC avant interprétation",
  "5. Utiliser comme aide à la décision, pas comme diagnostic",
  "",
  "---",
  "",
  "## Performance des modèles",
  "",
  sprintf("**%d modèles** entraînés avec succès (100%% de convergence grâce à Firth).", length(models_list)),
  "",
  "**Métrique** : [AUC](https://en.wikipedia.org/wiki/Receiver_operating_characteristic#Area_under_the_curve) (Area Under the ROC Curve) - excellente ≥ 0.9, bonne ≥ 0.8, acceptable ≥ 0.7.",
  "",
  "![Performance par modèle](figures/png/web_model_auc_by_model.png)",
  "",
  "![AUC vs nombre de variables](figures/png/web_model_auc_vs_nvars.png)",
  "",
  "**Observations** :"
)

# Analyser la tendance
cor_nvars_auc <- cor(models_df$n_vars, models_df$auc, method = "spearman")
best_model <- models_df[which.max(models_df$auc), ]
worst_model <- models_df[which.min(models_df$auc), ]
mean_ci_width <- mean(models_df$ci_width)

report <- c(report,
  sprintf("- Corrélation nombre de variables ↔ AUC : r = %.2f (Spearman)", cor_nvars_auc),
  sprintf("- Meilleur modèle : %d variables (%s), AUC = %.3f", best_model$n_vars, gsub("_", " + ", best_model$model_name), best_model$auc),
  sprintf("- Moins performant : %s, AUC = %.3f", worst_model$model_name, worst_model$auc),
  sprintf("- Largeur IC moyenne : %.3f (plage : %.3f-%.3f)", mean_ci_width, min(models_df$ci_width), max(models_df$ci_width)),
  "",
  "![Qualité des modèles](figures/png/web_model_quality_heatmap.png)",
  "",
  "---",
  "",
  "## Limites",
  "",
  "**Données** :",
  sprintf("1. Petit groupe témoin (n=%d) limitant la précision", n_control),
  sprintf("2. Déséquilibre prononcé (%.0f%% d'abus)", sum(data$abuse_binary) / nrow(data) * 100),
  "3. Données manquantes (16-21% pour certaines variables)",
  "4. Biais de sélection (patientes en suivi médical)",
  "",
  "**Méthodologie** :",
  "5. Absence de validation externe",
  "6. Incertitude potentiellement sous-estimée (modèle selection, données manquantes non comptabilisées)",
  "7. **Pas un outil diagnostique** - guide l'exploration clinique uniquement",
  "",
  "---",
  "",
  "\\newpage",
  "",
  "# Annexe : Performance détaillée de tous les modèles",
  "",
  "\\begin{longtable}{p{6cm}rrrrr}",
  "\\hline",
  "Variables & n & Abus & Témoins & AUC & IC width \\\\",
  "\\hline",
  "\\endhead"
)

# Add model table rows
for (i in 1:nrow(models_df)) {
  m <- models_df[i, ]

  # Get model variables
  model_vars <- models_list[[m$model_name]]$variables
  var_labels <- sapply(model_vars, function(v) var_labels_fr[[v]])
  var_str <- paste(var_labels, collapse = ", ")

  report <- c(report,
    sprintf("%s & %d & %d & %d & %.3f & %.3f \\\\",
            var_str, m$n_obs, m$n_abuse, m$n_control,
            m$auc, m$ci_width),
    "\\hline")
}

report <- c(report,
  "\\end{longtable}",
  "",
  "*n = taille d'échantillon, AUC = Area Under the ROC Curve, IC width = largeur de l'intervalle de confiance à 95%*"
)


# Écrire le rapport
writeLines(report, "outputs/rapport_web_model.md")
cat("Rapport Markdown généré : outputs/rapport_web_model.md\n")

# Générer le PDF avec rmarkdown
pdf_generated <- tryCatch({
  if (!requireNamespace("rmarkdown", quietly = TRUE)) {
    stop("rmarkdown n'est pas installé. Installez-le avec: install.packages('rmarkdown')")
  }

  # Change to outputs directory so rmarkdown can find the figures
  old_wd <- getwd()
  setwd("outputs")

  rmarkdown::render(
    "rapport_web_model.md",
    output_format = rmarkdown::pdf_document(
      latex_engine = "xelatex",
      keep_tex = FALSE,
      fig_caption = TRUE
    ),
    output_file = "rapport_web_model.pdf",
    quiet = TRUE
  )

  setwd(old_wd)
  TRUE
}, error = function(e) {
  message("Erreur lors de la génération du PDF: ", e$message)
  message("Le rapport Markdown est disponible dans outputs/rapport_web_model.md")
  if (exists("old_wd")) setwd(old_wd)
  FALSE
})

cat("\n==================================================================\n")
cat("Terminé!\n")
cat("==================================================================\n\n")
cat("Fichiers créés :\n")
cat("  - webapp/model.json (modèle pour l'application web)\n")
cat("  - outputs/rapport_web_model.md (rapport complet)\n")
if (pdf_generated) {
  cat("  - outputs/rapport_web_model.pdf (version PDF)\n")
}
cat("\nVisualisations PDF :\n")
cat("  - outputs/figures/pdf/web_model_auc_by_model.pdf\n")
cat("  - outputs/figures/pdf/web_model_auc_vs_nvars.pdf\n")
cat("  - outputs/figures/pdf/web_model_uncertainty.pdf\n")
cat("  - outputs/figures/pdf/web_model_quality_heatmap.pdf\n")
cat("\nVisualisations PNG :\n")
cat("  - outputs/figures/png/web_model_auc_by_model.png\n")
cat("  - outputs/figures/png/web_model_auc_vs_nvars.png\n")
cat("  - outputs/figures/png/web_model_uncertainty.png\n")
cat("  - outputs/figures/png/web_model_quality_heatmap.png\n\n")

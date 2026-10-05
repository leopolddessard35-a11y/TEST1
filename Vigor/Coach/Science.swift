import Foundation

/// Publication scientifique qui justifie une règle du coach.
struct Reference: Identifiable, Hashable {
    let id: String
    let citation: String
    /// Ce que l'étude montre, en une phrase.
    let finding: String
}

/// Bibliothèque des sources utilisées par les algorithmes de Vigor.
enum Science {
    static let plews2013 = Reference(
        id: "plews2013",
        citation: "Plews DJ, Laursen PB, Stanley J, Kilding AE, Buchheit M. Training adaptation and heart rate variability in elite endurance athletes. Sports Med. 2013;43(9):773-781.",
        finding: "La moyenne glissante sur 7 jours du log de la VFC (rMSSD) reflète mieux l'adaptation à l'entraînement qu'une mesure isolée.")
    static let kiviniemi2007 = Reference(
        id: "kiviniemi2007",
        citation: "Kiviniemi AM, Hautala AJ, Kinnunen H, Tulppo MP. Endurance training guided individually by daily heart rate variability measurements. Eur J Appl Physiol. 2007;101(6):743-751.",
        finding: "Adapter l'intensité du jour à la VFC du matin améliore davantage la VO2max qu'un plan fixe.")
    static let buchheit2014 = Reference(
        id: "buchheit2014",
        citation: "Buchheit M. Monitoring training status with HR measures: do all roads lead to Rome? Front Physiol. 2014;5:73.",
        finding: "VFC et FC de repos doivent être interprétées par rapport à la variabilité normale de l'individu (plus petit changement significatif).")
    static let hirshkowitz2015 = Reference(
        id: "hirshkowitz2015",
        citation: "Hirshkowitz M, et al. National Sleep Foundation's sleep time duration recommendations. Sleep Health. 2015;1(1):40-43.",
        finding: "Les adultes ont besoin de 7 à 9 h de sommeil par nuit.")
    static let mah2011 = Reference(
        id: "mah2011",
        citation: "Mah CD, Mah KE, Kezirian EJ, Dement WC. The effects of sleep extension on the athletic performance of collegiate basketball players. Sleep. 2011;34(7):943-950.",
        finding: "Allonger le sommeil vers 10 h au lit améliore vitesse, précision et humeur chez des sportifs.")
    static let milewski2014 = Reference(
        id: "milewski2014",
        citation: "Milewski MD, et al. Chronic lack of sleep is associated with increased sports injuries in adolescent athletes. J Pediatr Orthop. 2014;34(2):129-133.",
        finding: "Dormir moins de 8 h est associé à un risque de blessure 1,7 fois plus élevé.")
    static let phillips2017 = Reference(
        id: "phillips2017",
        citation: "Phillips AJK, et al. Irregular sleep/wake patterns are associated with poorer academic performance and delayed circadian and sleep/wake timing. Sci Rep. 2017;7:3216.",
        finding: "Un sommeil irrégulier d'un jour à l'autre dégrade les performances, à durée totale égale.")
    static let banister1975 = Reference(
        id: "banister1975",
        citation: "Banister EW, Calvert TW, Savage MV, Bach T. A systems model of training for athletic performance. Aust J Sports Med. 1975;7:57-61.",
        finding: "La performance résulte d'une « condition » qui se construit lentement et d'une « fatigue » qui se dissipe vite (modèle impulsion-réponse).")
    static let allenCoggan = Reference(
        id: "allenCoggan",
        citation: "Allen H, Coggan AR, McGregor S. Training and Racing with a Power Meter. 3rd ed. VeloPress; 2019.",
        finding: "TSS, CTL (42 j), ATL (7 j) et TSB : quantification de la charge à partir de la puissance relative à la FTP.")
    static let gabbett2016 = Reference(
        id: "gabbett2016",
        citation: "Gabbett TJ. The training–injury prevention paradox: should athletes be training smarter and harder? Br J Sports Med. 2016;50(5):273-280.",
        finding: "Un ratio charge aiguë / chronique au-delà de ~1,5 augmente fortement le risque de blessure ; 0,8–1,3 est la zone sûre.")
    static let foster1998 = Reference(
        id: "foster1998",
        citation: "Foster C. Monitoring training in athletes with reference to overtraining syndrome. Med Sci Sports Exerc. 1998;30(7):1164-1168.",
        finding: "Une monotonie élevée (charge quotidienne trop uniforme, > 2) précède souvent maladies et méforme.")
    static let seiler2010 = Reference(
        id: "seiler2010",
        citation: "Seiler S. What is best practice for training intensity and duration distribution in endurance athletes? Int J Sports Physiol Perform. 2010;5(3):276-291.",
        finding: "Les endurants performants passent ~80 % de leur temps à basse intensité et ~20 % à haute intensité.")
    static let mujika2003 = Reference(
        id: "mujika2003",
        citation: "Mujika I, Padilla S. Scientific bases for precompetition tapering strategies. Med Sci Sports Exerc. 2003;35(7):1182-1187.",
        finding: "Un affûtage de 1 à 2 semaines, volume −40 à −60 % en gardant l'intensité, améliore la performance d'environ 3 %.")
    static let bosquet2007 = Reference(
        id: "bosquet2007",
        citation: "Bosquet L, Montpetit J, Arvisais D, Mujika I. Effects of tapering on performance: a meta-analysis. Med Sci Sports Exerc. 2007;39(8):1358-1365.",
        finding: "L'affûtage optimal dure ~2 semaines avec une baisse progressive du volume de 41 à 60 %.")
    static let schoenfeld2017 = Reference(
        id: "schoenfeld2017",
        citation: "Schoenfeld BJ, Ogborn D, Krieger JW. Dose-response relationship between weekly resistance training volume and increases in muscle mass. J Sports Sci. 2017;35(11):1073-1082.",
        finding: "Chaque série hebdomadaire supplémentaire augmente l'hypertrophie ; ≥ 10 séries/muscle/semaine donnent les meilleurs gains.")
    static let wilson2012 = Reference(
        id: "wilson2012",
        citation: "Wilson JM, et al. Concurrent training: a meta-analysis examining interference of aerobic and resistance exercises. J Strength Cond Res. 2012;26(8):2293-2307.",
        finding: "L'endurance freine les gains de force et de masse, surtout la course ; le vélo interfère beaucoup moins.")
    static let morton2018 = Reference(
        id: "morton2018",
        citation: "Morton RW, et al. A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength. Br J Sports Med. 2018;52(6):376-384.",
        finding: "Le gain de masse plafonne vers 1,6 g de protéines/kg/jour (intervalle de confiance jusqu'à 2,2 g/kg).")
    static let iraki2019 = Reference(
        id: "iraki2019",
        citation: "Iraki J, Fitschen P, Espinar S, Helms E. Nutrition recommendations for bodybuilders in the off-season: a narrative review. Sports. 2019;7(7):154.",
        finding: "En prise de masse : surplus modéré de 10–20 % et prise de poids de 0,25 à 0,5 % du poids par semaine pour limiter le gras.")
    static let burke2011 = Reference(
        id: "burke2011",
        citation: "Burke LM, Hawley JA, Wong SHS, Jeukendrup AE. Carbohydrates for training and competition. J Sports Sci. 2011;29(Suppl 1):S17-S27.",
        finding: "Glucides : 3–5 g/kg les jours légers, 5–7 g/kg pour ~1 h/j d'entraînement, 6–10 g/kg pour 1 à 3 h/j.")
    static let jeukendrup2014 = Reference(
        id: "jeukendrup2014",
        citation: "Jeukendrup A. A step towards personalized sports nutrition: carbohydrate intake during exercise. Sports Med. 2014;44(Suppl 1):S25-S33.",
        finding: "Pendant l'effort : 30–60 g/h jusqu'à 2 h, jusqu'à 90 g/h (glucose + fructose) au-delà de 2 h 30.")
    static let mifflin1990 = Reference(
        id: "mifflin1990",
        citation: "Mifflin MD, St Jeor ST, et al. A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr. 1990;51(2):241-247.",
        finding: "Équation de référence pour estimer le métabolisme de base à partir du poids, de la taille, de l'âge et du sexe.")
    static let hall2008 = Reference(
        id: "hall2008",
        citation: "Hall KD. What is the required energy deficit per unit weight loss? Int J Obes. 2008;32(3):573-576.",
        finding: "Environ 7 700 kcal correspondent à 1 kg de variation de poids corporel (ordre de grandeur utilisé pour estimer la dépense réelle).")
    static let epley1985 = Reference(
        id: "epley1985",
        citation: "Epley B. Poundage chart. Boyd Epley Workout. Lincoln, NE: Body Enterprises; 1985.",
        finding: "1RM estimé = charge × (1 + répétitions / 30), fiable jusqu'à ~10 répétitions.")
    static let helms2016 = Reference(
        id: "helms2016",
        citation: "Helms ER, et al. Application of the repetitions in reserve-based rating of perceived exertion scale for resistance training. Strength Cond J. 2016;38(4):42-49.",
        finding: "Le RPE basé sur les répétitions en réserve permet d'ajuster la charge à la forme du jour.")
}

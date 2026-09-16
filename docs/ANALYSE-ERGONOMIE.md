# Analyse ergonomique de l'application Vitamine D

Analyse faite à partir du code SwiftUI (branche `main`, septembre 2026), sans exécution sur appareil : l'environnement d'analyse tourne sous Linux et ne peut pas compiler un projet Xcode. Ce qui suit décrit ce que le code construit à l'écran, et non des captures. Les points où une vérification sur iPhone s'impose sont signalés.

Elle sert aussi de liste de choses à régler **avant** la version Android : chaque défaut de structure corrigé ici est un défaut qu'on ne portera pas.

---

## 1. Verdict d'ensemble

L'application est bien pensée. La navigation à quatre onglets est juste, la décision principale (« sortir maintenant ou attendre ») est correctement placée en tête, les boutons ont des libellés d'action clairs (« Je sors », « Je rentre », « Je me retourne »), et les états vides sont tous prévus. La cohérence visuelle (cartes, filet d'or, tuiles) est tenue partout.

Le problème principal est ailleurs : **l'application explique trop, trop tôt et au même endroit qu'elle agit.** Presque chaque carte porte un paragraphe de justification, et plusieurs écrans cumulent trois ou quatre notices avant le premier bouton. Le résultat est un écran d'accueil qui demande beaucoup de défilement pour une question qui devrait se régler en un coup d'œil.

Le second problème est une **hiérarchie des paramètres éclatée** : la tenue, le lieu et les réglages de sommeil vivent dans trois endroits différents, et certains réglages sont dupliqués entre l'accueil et le profil.

| Aspect | État | Priorité de correction |
|---|---|---|
| Structure des onglets | Bonne | Aucune |
| Libellés des boutons | Bons | Faible |
| Densité de texte | Trop forte | **Haute** |
| Longueur de l'écran principal | Trop long | **Haute** |
| Emplacement des réglages | Dispersé | Moyenne |
| Accessibilité (VoiceOver, Dynamic Type) | Partielle | Moyenne |
| Cohérence des gestes | Bonne | Faible |

---

## 2. Écran principal (onglet Vitamine D)

C'est l'écran qu'on ouvre dix fois par jour. Dans l'ordre, il empile :

1. Titre et sous-titre (lieu, date)
2. Carte d'état : décompte de la fenêtre optimale, barre du jour, jauge UV, phrase de l'ombre, météo, trois tuiles, deux barres de progression
3. Carte Tenue : trois pourcentages, rangée de six pastilles vêtements, rangée de pastilles étoffes, ligne crème et chapeau
4. Jusqu'à **cinq notices** (hiver vitaminique, objectif hors de portée, peau encore chargée, soleil non comptabilisé, données modélisées)
5. Section Sortir : une ou deux cartes d'option, phrase de conseil, notice alertes refusées
6. Graphique de la journée
7. Carte « La journée » (sept lignes de faits)
8. Carte « Pourquoi ces heures » (deux paragraphes et un lien)
9. Carte « Ce que ceci n'est pas » (avertissement médical, deux paragraphes)

### 2.1 Ce qui fonctionne

- **Le décompte en tête** est la bonne décision. Il répond à la question avant tout le reste.
- **La tenue sur l'écran principal**, et non dans un réglage, est juste : c'est le paramètre qui bouge le plus souvent.
- **Les deux cartes « maintenant » et « plus tard »**, avec la préférée mise en évidence par la teinte et non par l'ordre, sont lisibles et honnêtes.
- **Le bouton « Je sors »** est unique, proéminent, et ne disparaît jamais tout à fait (« Je sors quand même » quand rien n'est conseillé).

### 2.2 Ce qui accroche

**A. Le bouton d'action est trop bas.** La section Sortir arrive après la carte d'état (déjà haute), la carte Tenue et les notices. Sur un iPhone standard, « Je sors » est très probablement sous la ligne de flottaison, et même deux écrans plus bas quand deux ou trois notices s'affichent. Or c'est le seul bouton qui compte.

Deux pistes, à choisir :
- Remonter la section Sortir **juste sous le décompte**, et reléguer jauge UV, météo et tuiles dans une carte « Maintenant » sous les options de sortie.
- Ou garder l'ordre mais réduire la carte d'état à l'essentiel (décompte et barre du jour) et déplacer le reste dans une carte dépliable.

**B. Les notices s'accumulent.** Cinq conditions peuvent afficher chacune une bannière de trois à six lignes. Deux ou trois en même temps est un cas courant en automne (« peau encore chargée » plus « objectif hors de portée » plus « soleil non comptabilisé »). Proposition : une seule zone de notices, limitée à la plus importante, avec un lien « et 2 autres » qui déplie le reste. Les notices d'information (données modélisées, soleil non comptabilisé) devraient être des lignes d'une phrase, pas des bannières.

**C. Les paragraphes explicatifs sont sur le mauvais écran.** « Pourquoi ces heures » et l'avertissement médical complet sont des textes de référence qu'on lit une fois. Ils ont leur place dans Profil › Comprendre (où ils existent déjà) ou dans l'accueil de premier lancement (où ils existent aussi). Sur l'écran principal, un seul lien « Pourquoi ces heures ? » suffit. L'avertissement médical peut se réduire à la version compacte d'une phrase.

**D. La carte « La journée » répète le décompte.** Lever, coucher, midi solaire, hauteur maximale, fenêtre optimale : ces faits sont déjà dans la barre du jour et le graphique. Les regrouper dans le graphique (annotations au survol ou légende) libérerait une carte entière.

**E. Deux boutons de rafraîchissement.** Il y a la flèche circulaire dans la barre et le tirer-pour-rafraîchir. Le premier est redondant sur iOS ; il est en revanche utile comme repère visuel de « en cours ». À conserver seulement s'il affiche un indicateur de chargement, sinon à retirer.

**F. La pastille de lieu mène à l'année, pas au lieu.** Le bouton en haut à gauche porte le nom du lieu et une icône de position. Toucher un lieu, c'est s'attendre à le changer. Or il ouvre la vue de l'année, où se trouve ensuite un bouton « Changer de lieu ». Le raisonnement du code (l'année est la seule vue qui montre l'hiver vitaminique) est bon, mais le geste est trompeur. Solution simple : la pastille ouvre le sélecteur de lieu, et la vue de l'année devient une carte cliquable sur l'écran principal (« Votre année à Montréal : 4 mois sans synthèse »), ou un lien dans la carte « La journée ».

### 2.3 La carte Tenue

Bien conçue dans l'idée, mais chargée. Trois pourcentages avec un « + » et un « = » entre eux, deux rangées de pastilles à défilement horizontal, une ligne de résumé et un bouton texte « Crème, chapeau, régions ».

- **Le calcul affiché (peau nue + par l'étoffe = surface utile)** est exact mais intimidant. Un seul chiffre (surface utile) avec une ligne en dessous (« 18 % de peau nue, coton ordinaire ») dit la même chose sans opération à lire.
- **Les pastilles d'étoffe sont un second choix imposé.** La tenue suggère déjà une étoffe. La rangée pourrait être repliée par défaut sous un lien « Étoffe : coton ordinaire › » et n'apparaître qu'au toucher. Cela retire une rangée de 92 points de haut sur l'écran principal.
- **Le libellé « Crème, chapeau, régions »** est une liste, pas une action. Préférer « Ajuster la tenue » ou « Plus d'options ».
- **Le défilement horizontal des pastilles** cache les tenues de droite (« Camisole », « Maillot ») sur un iPhone étroit. Vérifier sur appareil qu'au moins la moitié de la septième pastille dépasse du bord, sinon l'utilisateur ne sait pas qu'il y en a d'autres.

### 2.4 Pendant une sortie

L'état « Vous êtes dehors » est le meilleur écran de l'application : chronomètre géant, trois tuiles, un bouton « Je rentre » dont la couleur suit le niveau de risque. Deux remarques :

- **« J'étais sorti avant »** est un bouton de correction placé sous le bouton principal, en petite police. C'est le bon endroit, mais son libellé devrait dire ce qu'il fait : « Corriger l'heure de départ ».
- **La carte Position** (debout, ventre, dos) porte un paragraphe de huit lignes quand on est debout. Une seule phrase suffit : « Passez à Ventre ou Dos si vous vous allongez. »
- **La carte « Prochaines alertes »** explique que les alertes sont programmées mais ne les liste pas. Afficher les trois heures (objectif, seuil d'alerte, arrêt) serait plus utile que le paragraphe qui les décrit.

---

## 3. Onglet Sommeil

Neuf cartes en colonne : préambule, aujourd'hui, déplacement du lever (conditionnel), le soir, routine, lumière artificielle, outils, réglages, avertissement.

### 3.1 Ce qui fonctionne

- La séparation en onglet distinct de la vitamine D est justifiée et bien expliquée.
- Les cartes « Votre routine » et « Les outils » qui sont elles-mêmes des liens (toute la carte est cliquable, chevron à droite) sont un bon modèle.
- La routine du sommeil (neuf étapes, un interrupteur chacune, « Pourquoi » dépliable) est le meilleur exemple dans l'application d'explication **à la demande** plutôt qu'imposée.

### 3.2 Ce qui accroche

**A. Le préambule prend la place de la donnée.** La première carte est un paragraphe qui explique pourquoi cet onglet existe. La fenêtre du matin (l'information utile) arrive en deuxième. Inverser : la fenêtre en premier, et le paragraphe réduit à une ligne sous le titre de l'écran (« Lumière du matin pour l'horloge interne, sans lien avec la vitamine D »).

**B. Les réglages sont en bas d'un écran de lecture.** Lever habituel, lever visé, durée de sommeil, suivi activé : ces quatre réglages conditionnent tout ce qui est au-dessus, et ils sont en huitième position. La carte « Votre routine » dit d'ailleurs « Modifiez le lever visé dans les réglages de l'onglet Sommeil », ce qui envoie l'utilisateur chercher. Proposer : un bouton engrenage dans la barre de navigation de l'onglet Sommeil qui ouvre ces réglages en feuille.

**C. Deux cartes pour la lumière artificielle.** « Lumière artificielle » (lien vers les minuteurs) et « Les outils » (lien vers le catalogue) se recouvrent : les lampes de luminothérapie sont dans les deux. Fusionner en une carte « Lampes et outils » avec deux lignes cliquables.

**D. L'onglet s'appelle « Sommeil » mais l'écran parle de lumière.** Le titre de l'onglet et de l'écran est « Sommeil », le contenu est « lumière du matin, lumière du soir, lampes ». « Horloge » ou « Lumière » serait plus exact, mais « Sommeil » est ce que les gens cherchent. À garder, en s'assurant que la première carte parle bien de sommeil (heure de coucher visée, heure de lever) avant de parler de lux.

---

## 4. Onglet Historique

Résumé (trois tuiles), graphique de deux semaines, carte des réserves (trois tuiles, graphique, verdict, avertissement), carte hiver (trois tuiles, réserve, prévision, conseil), liste des sorties.

### 4.1 Ce qui fonctionne

- Le bouton « + » dans la barre pour ajouter une sortie oubliée est à l'endroit attendu.
- La liste des sorties est claire : date, durée, lieu, peau exposée, UI, DEM. Le marqueur « saisie à la main » est une bonne idée.
- L'état vide propose l'action (« Ajouter une sortie oubliée »).

### 4.2 Ce qui accroche

**A. Deux cartes de réserve qui disent la même chose.** « Vos réserves » et « Avant l'hiver » affichent toutes deux la réserve estimée, une projection, et un avertissement sur le 25(OH)D. Le texte sur la demi-vie est répété presque mot pour mot. Fusionner en une carte « Réserves et hiver » avec un seul graphique (passé, présent, projection, zone d'hiver ombrée).

**B. Six tuiles de métriques pour la réserve** (apport équivalent, recommandé, demi-vie, l'hiver commence, jours utiles, dont optimaux). La demi-vie est une constante, pas une donnée personnelle ; elle appartient au glossaire. « Dont optimaux » est un raffinement. Garder trois tuiles : apport équivalent, jours utiles avant l'hiver, réserve prévue à l'entrée de l'hiver.

**C. La liste des sorties est en dernier.** Sur un écran nommé « Historique », l'historique arrive après quatre cartes d'analyse. Placer la liste juste après le résumé, et l'analyse des réserves en dessous. Ou mieux : un sélecteur segmenté en haut (« Sorties | Réserves ») qui évite le défilement.

**D. Aucune suppression rapide.** Supprimer une sortie exige d'ouvrir la fiche, de défiler jusqu'au bouton rouge, puis de confirmer. Un balayage vers la gauche sur la ligne est le geste attendu sur iOS. Facile à ajouter avec `swipeActions` si la liste passe en `List`.

---

## 5. Onglet Profil

Un formulaire de onze sections : phototype, vous, exposition, morphologie, objectifs, alertes, santé, apport alimentaire (conditionnel), retirer les données (conditionnel), comprendre, méthode.

### 5.1 Ce qui fonctionne

- Le formulaire natif iOS est le bon choix pour cet écran.
- Les lignes de phototype avec pastille de couleur et coche sont limpides.
- « Refaire le questionnaire » à côté du titre Phototype est bien placé.
- La suggestion d'objectif affichée en permanence avec un bouton « Adopter » est un bon modèle.

### 5.2 Ce qui accroche

**A. Les pieds de section sont des articles.** Le pied de « Exposition » fait trois paragraphes, celui de « Santé » quatre, celui de « Méthode » deux. Sur iOS, un pied de section est une ligne ou deux. Le reste devrait vivre derrière un bouton « En savoir plus » ou dans les pages Méthode et Glossaire qui existent déjà.

**B. La tenue est réglée à deux endroits.** Profil › Exposition › « Tenue habituelle » ouvre la même feuille que l'écran principal. C'est voulu (tenue habituelle contre tenue du moment), mais rien ne le dit, et les deux modifient le même champ du profil. Soit retirer la section du profil (l'écran principal suffit), soit la nommer clairement « Tenue par défaut au lancement » et la distinguer dans le modèle.

**C. Six lignes en lecture seule dans « Exposition ».** Peau exposée, étoffe, surface équivalente, maximum aujourd'hui, plafond théorique : ce sont des résultats de calcul, pas des réglages. Dans un formulaire, ils passent pour des champs qu'on ne peut pas modifier. Les déplacer vers une page « Vos chiffres » accessible par un lien, ou dans le glossaire.

**D. La section Santé est la plus longue de l'application.** Deux interrupteurs, un bouton de demande d'accès, un état, une phrase sur l'écriture, une phrase sur ce qu'Apple ne révèle pas, deux lignes de données, un bouton pour ouvrir Santé, un pied de quatre paragraphes, puis deux sections supplémentaires. Le code explique que cette verbosité vient d'un vrai problème (iOS ne redemande jamais l'autorisation), mais l'utilisateur moyen n'active jamais Santé et défile devant tout ça. Proposer : une seule ligne « Santé › » qui ouvre une page dédiée avec tout le détail.

**E. « Comprendre » et « Méthode » sont deux sections pour une même chose.** Fusionner en une section « En savoir plus » de cinq liens : Revoir la présentation, À quoi sert la vitamine D, Glossaire, Méthode et limites, Sources.

**F. Le poids et la taille apparaissent deux fois** (accueil et profil), ce qui est normal, mais la note « Facultatif, sans effet sur les durées » est répétée dans les deux. Une fois suffit.

---

## 6. Accueil de premier lancement

Douze étapes : trois pages d'explication, âge, morphologie, ascendance, cinq questions, résultat.

- **Trois pages de texte avant la première question** est beaucoup. Les gens qui installent une application « Vitamine D » savent déjà pourquoi. Proposer une seule page d'explication avec trois puces, et garder les deux autres pages dans Profil › Comprendre.
- **« Passer »** existe dans la barre mais n'apparaît qu'à partir de la deuxième page. Il devrait être là dès la première.
- **La barre de progression** compte les pages d'explication comme des étapes : l'utilisateur voit « 3 sur 12 » avant d'avoir répondu à quoi que ce soit. Compter seulement les étapes de saisie.
- **Le bouton final** dit « Commencer » au premier lancement et « Terminer » en révision. Bien.
- **La page de résultat** permet d'ajuster le phototype à la main, ce qui est excellent. Mais la liste des six types utilise le chiffre romain plus le résumé, alors que le profil utilise le titre plus le résumé. Harmoniser.

---

## 7. Cohérence des boutons et des gestes

| Élément | Constat | Recommandation |
|---|---|---|
| « Je sors » / « Je rentre » | Clairs, proéminents, cohérents | Garder |
| « Je me retourne » | Clair | Garder |
| « J'étais sorti avant » | Décrit un état, pas une action | « Corriger l'heure de départ » |
| « Crème, chapeau, régions » | Énumération | « Ajuster la tenue » |
| « Voir les rayons passer » | Poétique mais vague | « Voir pourquoi (schéma) » |
| « Voir les trois, et leurs minuteurs » | Suppose qu'on a lu la carte | « Lampes et minuteurs » |
| « Que veulent dire ces chiffres ? » | Question, bien | Garder |
| « Sortie oubliée » (barre) | Icône « + » seule visible | Garder, l'icône suffit |
| « Parfait » (alerte fin de sortie) | Chaleureux mais inhabituel | « OK » ou garder si assumé |
| Bouton info (i) près des chiffres | Discret, tertiaire | Vérifier la taille de la zone de touche (44 pt) |
| Pastille de lieu (barre) | Mène à l'année, pas au lieu | Voir 2.2 F |
| Flèche de rafraîchissement | Doublon du tirer-pour-rafraîchir | Retirer ou animer |

Les feuilles modales sont cohérentes : « Terminé » ou « Fermer » en haut à droite, « Annuler » à gauche quand il y a une saisie. Les suppressions demandent confirmation. Le retour arrière est partout celui du système. Rien à redire sur ce plan.

---

## 8. Accessibilité

- **VoiceOver** : seuls quatre composants portent des étiquettes (titre d'écran, jauge UV, décompte, bouton glossaire). Les pastilles de tenue et d'étoffe n'annoncent pas leur état sélectionné. Les tuiles de métriques lisent l'intitulé et la valeur séparément. Les graphiques Swift Charts n'ont pas de description. Le bouton « Je rentre » teinté par le risque n'annonce pas le niveau de risque.
- **Dynamic Type** : plusieurs tailles sont fixées en points (titre à 30, chronomètre à 54, pastilles à 84 et 92 de large, jauge à 108). Aux grandes tailles d'accessibilité, les pastilles de tenue vont déborder ou se tronquer. À vérifier sur appareil avec la taille « AX3 ».
- **Contraste** : le texte sur fond de ciel (titres serif, sous-titre or) est géré par une couleur `onSky` dédiée, ce qui montre que le sujet a été traité. À vérifier au coucher du soleil, quand le dégradé passe par l'orange.
- **Cibles tactiles** : les boutons glossaire en `caption2` sont probablement sous les 44 points recommandés. Ajouter un `contentShape` élargi.

---

## 9. Ce qu'il faut régler avant la version Android

Par ordre d'importance, ce qui devrait être tranché sur iOS d'abord pour ne pas porter deux fois :

1. **Ordre de l'écran principal** : décider une fois pour toutes où va la section Sortir (voir 2.2 A). C'est la décision qui structure toute la maquette Android.
2. **Politique sur les textes explicatifs** : une règle simple, du genre « une phrase sur l'écran d'action, le reste derrière un lien ». Appliquée partout, elle retire un tiers du défilement.
3. **Emplacement unique des réglages** : profil pour la personne, engrenage dans l'onglet Sommeil pour l'horloge, écran principal pour la tenue du moment. Retirer la tenue du profil.
4. **Fusion des cartes redondantes** dans Historique et Sommeil.
5. **Geste de la pastille de lieu.**

Ce qui est spécifique à Android et n'a pas d'équivalent à porter tel quel :

- **Activités en direct et île dynamique** n'existent pas. L'équivalent est une notification permanente de service au premier plan avec chronomètre, ce qui est en fait plus simple à faire.
- **WeatherKit** est Apple seulement. L'application a déjà Open-Meteo en repli, qui devient le service principal sur Android.
- **HealthKit** devient Health Connect. Le modèle d'autorisation y est différent (redemandable), ce qui simplifie toute la section Santé.
- **Le formulaire iOS** (`Form`) n'a pas d'équivalent direct. L'écran Profil devra être redessiné en liste Material 3 avec des en-têtes de section, ce qui est une bonne occasion d'appliquer les réductions du point 5.
- **Les pastilles de tenue** deviennent des `FilterChip` Material, qui gèrent nativement l'état sélectionné et l'accessibilité.
- **La barre d'onglets** devient une `NavigationBar` Material 3, quatre destinations, même structure.

Le moteur de calcul (`Engine/`, environ 3 400 lignes de Swift sans dépendance) est le cœur à porter. Deux voies : le traduire en Kotlin (fidèle, testable avec les 98 tests existants traduits), ou passer par Kotlin Multiplatform pour partager le moteur entre les deux applications. La seconde voie évite les divergences futures mais impose de réécrire le moteur iOS en Kotlin aussi. Ce choix mérite une discussion à part.

---

## 10. Résumé des recommandations

**Haute priorité, faible effort**

- Remonter la section Sortir sous le décompte.
- Réduire chaque notice d'information à une ligne ; n'afficher qu'une bannière à la fois.
- Retirer « Pourquoi ces heures » et l'avertissement complet de l'écran principal (garder un lien et une phrase).
- Renommer « J'étais sorti avant », « Crème, chapeau, régions », « Voir les rayons passer ».
- Faire ouvrir le sélecteur de lieu par la pastille de lieu.

**Moyenne priorité**

- Replier la rangée d'étoffes par défaut.
- Mettre les réglages de sommeil derrière un engrenage.
- Fusionner les deux cartes de réserve dans Historique et remonter la liste des sorties.
- Réduire les pieds de section du profil à deux lignes ; déplacer Santé dans une page dédiée.
- Réduire l'accueil à une page d'explication.

**À vérifier sur appareil**

- Position de « Je sors » sur iPhone SE et iPhone 16 à la taille de police par défaut et à AX3.
- Débordement des pastilles de tenue aux grandes tailles.
- Contraste du texte sur ciel au crépuscule.
- Zones tactiles des boutons glossaire.

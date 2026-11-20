// Les regles du site YouTube surveille, sans DOM : ce qui peut s'ouvrir et ce
// qui peut s'afficher, d'apres les approbations partagees. Script classique
// (charge tel quel par le script de contenu, et importe par les tests).
(() => {
  // Ce qu'on a besoin de savoir des approbations, en ensembles.
  function portes(doc) {
    const chaines = doc?.chaines ?? [];
    return {
      videos: new Set((doc?.videos ?? []).map((v) => v.id)),
      listes: new Set((doc?.listes ?? []).map((l) => l.id)),
      chaines: new Set(chaines.map((c) => c.id)),
      nomsChaines: new Set(chaines.map((c) => normaliser(c.nom))),
    };
  }

  const normaliser = (t) => (t ?? "").normalize("NFC").trim().toLowerCase();

  // La page entiere : "ok", "bloque", ou "chaine" quand seule la chaine de la
  // video peut trancher.
  function page(adresse, p) {
    const url = new URL(adresse);
    const v = url.searchParams.get("v");
    const liste = url.searchParams.get("list");
    switch (url.pathname) {
      case "/results":
        return "ok";
      case "/watch":
        if (!v) return "bloque";
        if (p.videos.has(v) || (liste && p.listes.has(liste))) return "ok";
        return "chaine";
      case "/playlist":
        return liste && p.listes.has(liste) ? "ok" : "bloque";
      default:
        return "bloque";
    }
  }

  // Une chaine se reconnait a son identifiant (UC…) quand le lien le donne,
  // sinon a son nom.
  function chaineApprouvee({ id, nom }, p) {
    return (id && p.chaines.has(id)) || (!!nom && p.nomsChaines.has(normaliser(nom)));
  }

  // Un resultat de recherche, decrit par ses liens. Une liste d'une chaine
  // approuvee passe aussi : ses videos s'ouvriront par la chaine.
  function resultat({ video, liste, chaine }, p) {
    if (liste) return p.listes.has(liste) || chaineApprouvee(chaine ?? {}, p);
    if (video) return p.videos.has(video) || chaineApprouvee(chaine ?? {}, p);
    return !!chaine && chaineApprouvee(chaine, p);
  }

  // Lit les identifiants d'un lien YouTube relatif ou absolu.
  function lien(href) {
    if (!href) return {};
    const url = new URL(href, "https://www.youtube.com");
    const canal = url.pathname.match(/^\/channel\/(UC[\w-]{22})/);
    return {
      video: url.pathname === "/watch" ? url.searchParams.get("v") : null,
      liste: url.pathname === "/playlist" ? url.searchParams.get("list") : null,
      chaine: canal ? canal[1] : null,
    };
  }

  globalThis.GardienYouTube = { portes, page, chaineApprouvee, resultat, lien };
})();

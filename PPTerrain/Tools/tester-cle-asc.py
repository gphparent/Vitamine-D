"""Eprouve le trio cle / identifiant / emetteur contre l'API App Store Connect.

Xcode signale un refus 401 au milieu d'un archivage, sans dire laquelle des
trois valeurs est en cause. Un appel direct le dit en une seconde, et confirme
au passage que la fiche de l'application est visible par la cle.

Ne depend que de la bibliotheque standard et d'openssl : ni PyJWT ni
cryptography ne sont installes sur les executeurs.
"""
import base64, json, subprocess, sys, time, urllib.request, urllib.error


def b64url(donnees: bytes) -> str:
    return base64.urlsafe_b64encode(donnees).rstrip(b'=').decode()


def der_vers_brut(der: bytes) -> bytes:
    """Convertit une signature ECDSA du format DER vers r||s sur 64 octets.

    openssl signe en DER ; JWS attend les deux entiers concatenes, chacun
    complete a gauche sur 32 octets.
    """
    if der[0] != 0x30:
        raise ValueError("signature DER attendue")
    i = 2
    if der[1] & 0x80:                      # longueur sur plusieurs octets
        i = 2 + (der[1] & 0x7F)
    nombres = []
    for _ in range(2):
        if der[i] != 0x02:
            raise ValueError("entier DER attendu")
        longueur = der[i + 1]
        valeur = der[i + 2:i + 2 + longueur].lstrip(b'\x00')
        nombres.append(valeur.rjust(32, b'\x00'))
        i += 2 + longueur
    return nombres[0] + nombres[1]


def jeton(chemin_cle: str, key_id: str, issuer_id: str,
          individuelle: bool = False) -> str:
    """Forge un JWT ES256 pour l'API App Store Connect.

    Apple distingue deux sortes de cles, creees depuis deux flux differents,
    et leurs jetons ne se ressemblent pas :

    - une **cle d'equipe** se reclame de son emetteur par le champ `iss` ;
    - une **cle individuelle** n'a pas d'emetteur et porte `sub: "user"`.

    Presenter la mauvaise forme donne un 401 sec, sans plus d'explication.
    """
    entete = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    maintenant = int(time.time())
    charge = {
        "iat": maintenant,
        "exp": maintenant + 600,           # Apple refuse au-dela de vingt minutes
        "aud": "appstoreconnect-v1",
    }
    if individuelle:
        charge["sub"] = "user"
    else:
        charge["iss"] = issuer_id
    a_signer = f"{b64url(json.dumps(entete, separators=(',', ':')).encode())}." \
               f"{b64url(json.dumps(charge, separators=(',', ':')).encode())}"
    der = subprocess.run(
        ['openssl', 'dgst', '-sha256', '-sign', chemin_cle, '-binary'],
        input=a_signer.encode(), capture_output=True, check=True).stdout
    return f"{a_signer}.{b64url(der_vers_brut(der))}"


def essayer(chemin_cle: str, key_id: str, issuer_id: str, individuelle: bool):
    """Interroge /v1/apps. Rend les donnees, ou le code HTTP du refus."""
    requete = urllib.request.Request(
        "https://api.appstoreconnect.apple.com/v1/apps?limit=200"
        "&fields[apps]=bundleId,name",
        headers={"Authorization":
                 f"Bearer {jeton(chemin_cle, key_id, issuer_id, individuelle)}"})
    try:
        with urllib.request.urlopen(requete, timeout=30) as reponse:
            return json.load(reponse), None
    except urllib.error.HTTPError as erreur:
        return None, erreur.code


def main() -> int:
    chemin_cle, key_id, issuer_id = sys.argv[1], sys.argv[2], sys.argv[3]
    attendu = sys.argv[4] if len(sys.argv) > 4 else None

    # On essaie la forme « cle d'equipe » d'abord, puis la forme individuelle :
    # c'est le seul moyen de savoir laquelle des deux a ete creee.
    donnees, refus = essayer(chemin_cle, key_id, issuer_id, individuelle=False)

    if donnees is None:
        donnees_ind, refus_ind = essayer(chemin_cle, key_id, issuer_id,
                                         individuelle=True)
        if donnees_ind is not None:
            print("Cette cle est une CLE INDIVIDUELLE, pas une cle d'equipe.")
            print()
            print("  Elle s'authentifie, mais elle n'a pas acces aux points")
            print("  d'acces de provisionnement, dont la signature infonuagique")
            print("  a besoin : elle ne pourra jamais archiver ni exporter.")
            print()
            print("  Il faut une cle d'equipe : App Store Connect, Utilisateurs")
            print("  et acces, Integrations, section « Cles de l'equipe » — et")
            print("  non « Cles individuelles » — avec le role Admin.")
            return 1

        print(f"Apple refuse les identifiants : HTTP {refus}")
        if refus == 401:
            print("  Les deux formes de jeton sont refusees, celle d'une cle")
            print("  d'equipe comme celle d'une cle individuelle.")
            print()
            print("  Les trois valeurs sont bien formees mais ne vont pas")
            print("  ensemble, ou la cle a ete revoquee. La cause la plus")
            print("  frequente est un ASC_KEY_ID qui ne correspond pas au .p8")
            print("  colle : recollez les deux depuis la meme cle, d'un coup.")
        return 1

    apps = donnees.get('data', [])
    print(f"Identifiants acceptes. {len(apps)} fiche(s) visible(s) par cette cle.")
    identifiants = [a['attributes'].get('bundleId') for a in apps]
    for app in apps:
        attrs = app['attributes']
        print(f"  {attrs.get('bundleId')}  —  {attrs.get('name')}")
    if attendu and attendu not in identifiants:
        print(f"\nLa fiche '{attendu}' n'est pas visible par cette cle.")
        print("  Verifiez l'identifiant de paquet, ou les droits de la cle.")
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())

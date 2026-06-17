Guide rapide — Lancer le backend en local

Prérequis
- Go (>=1.20)
- Docker (optionnel pour Postgres)
- Une console PowerShell (Windows) ou bash (Linux/macOS)

1) Lancer Postgres (option Docker)
```powershell
# Exécute Postgres en local (image officielle)
docker run --name p2p-dev-db -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=p2p_dev -p 5432:5432 -d postgres:15
```

2) Vérifier la base de données
- DB: `p2p_dev`, user: `postgres`, password: `postgres`
- Si vous préférez créer manuellement la DB, connectez-vous et créez `p2p_dev`.

3) Lancer le backend (PowerShell)
```powershell
# Depuis le dossier backend
cd backend
# Exemple : utilise la DB docker et un secret de dev
.\scripts\run-dev.ps1 -DatabaseUrl "postgres://postgres:postgres@localhost:5432/p2p_dev?sslmode=disable" -JwtSecret "dev-secret"
```

4) Points importants
- Le backend lira `DATABASE_URL`; si elle est absente il utilisera le store en mémoire (pas de Postgres connecté).
- `ALLOW_INSECURE_DEV=true` permet d'utiliser le secret `dev-secret` sans bloquer le démarrage.
- Les migrations sont appliquées automatiquement au démarrage si Postgres est configuré.

5) Lier l'app mobile
- Sur un émulateur Android classique (AVD), utilisez l'URL `http://10.0.2.2:8080`.
- Sur un appareil physique, remplacez par l'IP de votre PC (ex: `http://192.168.1.42:8080`).

Exemple pour lancer Flutter vers un appareil physique :
```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.42:8080
```

Exemple pour l'émulateur Android :
```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

6) Dépannage rapide
- Erreur de connexion DB : vérifiez que Postgres écoute sur 127.0.0.1:5432 et que `DATABASE_URL` est correcte.
- Si le backend démarre mais mobile échoue : vérifier `API_BASE_URL` et pare-feu.

Si vous voulez, je peux :
- ajouter un script `run-mobile-dev.ps1` pour lancer mobile + backend ensemble,
- appliquer `ResponsivePage` sur toutes les pages restantes.

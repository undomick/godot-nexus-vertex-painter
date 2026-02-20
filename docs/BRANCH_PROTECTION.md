# Branch Protection einrichten

Branch Protection sorgt dafür, dass Änderungen nur per Pull Request und mit bestandenem CI-Build in die Haupt-Branch gelangen. Da dies über die GitHub-Weboberfläche konfiguriert wird, kann es nicht per Repo-Dateien gesetzt werden.

## Schritte

1. Öffne **Settings** des Repositories auf GitHub.
2. Gehe zu **Branches** (unter "Code and automation").
3. Unter **Branch protection rules** klicke **Add branch protection rule** (oder bearbeite die bestehende Regel).
4. **Branch name pattern**: `main` oder `master` (je nachdem, welcher Branch euer Standard-Branch ist).
5. Aktiviere:
   - **Require a pull request before merging** (optional: "Require approvals" setzen).
   - **Require status checks to pass before merging**.
6. Unter **Status checks that are required**:
   - Wähle **Search for status checks** und suche nach `Linux`, `Windows`, `macOS` (die Jobs aus dem Build GDExtension Workflow).
   - Oder gib `build-linux` / `build-windows` / `build-macos` ein, falls die Job-Namen dort auftauchen.
   - Alternativ reicht es oft, **"Build GDExtension"** als erforderlichen Check zu setzen, sofern der gesamte Workflow als ein Check erscheint.
7. Speichere mit **Create** bzw. **Save changes**.

## Resultat

- Pull Requests können nur gemerged werden, wenn der Build-Workflow erfolgreich durchläuft.
- Direkte Pushes auf die geschützte Branch sind blockiert (außer für Admins, falls nicht explizit deaktiviert).
- Der `main`/`master`-Branch bleibt dadurch stets build-fähig.

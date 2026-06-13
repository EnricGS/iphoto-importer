# Instal·lacions d'eines i skills

Data inici: 2026-04-12

## Resum

Document de seguiment de totes les eines, skills i extensions instal·lades durant la sessió.
Context: migració de tots els projectes a local (eliminant Vercel, Supabase), afegint Gemma 4 i pipelines de fotos en local.

---

## Eines instal·lades

| # | Eina | Descripció | Data | Estat |
|---|------|-----------|------|-------|
| 1 | Everything Claude Code (ECC) v1.10.0 | Toolkit d'agents, skills, commands i rules per Claude Code | 2026-04-12 | Instal·lat |
| 2 | Impeccable v2.1.7 | Design language anti-AI-slop: skills de disseny + CLI detector anti-patrons | 2026-04-12 | Instal·lat |
| 3 | Expect CLI v0.1.3 | Testing automàtic en browser real: llegeix git diff, genera tests, executa amb Playwright | 2026-04-12 | Instal·lat |
| 4 | Graphify v0.4.6 | Knowledge graph de codi/docs/media → query amb 71x menys tokens | 2026-04-12 | Instal·lat |
| 5 | AIDesigner.ai | MCP server per generar/refinar UI HTML via IA (connectat via OAuth) | 2026-04-12 | Connectat |

---

## Guia d'ús: quan i com fer servir cada eina

### Workflow complet per fase de projecte

```
FASE 1: INICI DE PROJECTE
  graphify .                    → Mapejar codebase existent
  /plan                         → Planificar implementació (ECC planner)

FASE 2: DISSENY UI
  AIDesigner generate_design    → Generar primer disseny HTML
  /impeccable-shape             → Planificar UX/UI abans de codificar
  AIDesigner refine_design      → Iterar sobre el disseny

FASE 3: IMPLEMENTACIÓ
  /tdd                          → Cicle test-driven development
  /build-fix                    → Resoldre errors de build
  graphify query "..."          → Consultar el graf per entendre dependències

FASE 4: QUALITAT
  /code-review                  → Revisió automàtica de canvis
  /security-review              → Auditoria seguretat
  /impeccable-audit             → Auditoria tècnica UI (a11y, performance)
  /impeccable-critique          → Avaluació UX
  /expect                       → Tests automàtics en browser real

FASE 5: POLISH
  /impeccable-polish            → Pas final: spacing, consistència, detalls
  npx impeccable detect .       → Escaneig anti-patrons AI slop
  /verify                       → Verificació final

FASE 6: MANTENIMENT
  graphify . --update           → Actualitzar graf incremental
  /refactor-clean               → Netejar codi obsolet
```

### Detall per eina

#### ECC (Everything Claude Code) — El sistema base

**Quan:** Sempre actiu. Proporciona agents, rules i commands a totes les sessions.

| Situació | Què usar |
|----------|---------|
| Començar funcionalitat nova | `/plan` → planner agent |
| Escriure codi | `/tdd` → tdd-guide agent (tests primer) |
| Codi acabat d'escriure | `/code-review` → code-reviewer agent |
| Build falla | `/build-fix` → build-error-resolver agent |
| Tocar auth, secrets, input | `/security-review` → security-reviewer agent |
| Migrar DB | Skill `database-migrations` + `postgres-patterns` |
| Configurar Docker | Skill `docker-patterns` + `deployment-patterns` |
| Pipeline IA | Skill `pytorch-patterns` + `agent-harness-construction` |
| Decidir Gemma vs Claude API | Skill `cost-aware-llm-pipeline` |
| Netejar codi Supabase/Vercel | `/refactor-clean` → refactor-cleaner agent |
| Tests end-to-end | `/e2e` → e2e-runner agent |
| Verificació final | `/verify` → verification-loop |

#### AIDesigner — Generació de UI

**Quan:** Crear o redissenyar qualsevol interfície web.

| Situació | Command |
|----------|---------|
| Crear UI des de zero | `generate_design` amb prompt + repo_context |
| Millorar UI existent | `refine_design` amb run_id + feedback |
| Clonar un disseny de referència | `generate_design` amb mode="clone" + url |
| Inspirar-se en un web | `generate_design` amb mode="inspire" + url |
| Millorar un web existent | `generate_design` amb mode="enhance" + url |
| Versió mòbil | viewport="mobile" |
| Comprovar crèdits | `get_credit_status` |

**Workflow típic:**
1. `generate_design` → primer draft HTML
2. `refine_design` → iterar amb feedback ("més contrast", "canvia tipografia")
3. Copiar HTML resultant al projecte
4. Adaptar a Next.js/React components

#### Impeccable — Qualitat de disseny

**Quan:** Després de generar UI (amb AIDesigner o manualment), abans de lliurar.

| Situació | Command |
|----------|---------|
| Avaluar qualitat general | `/impeccable-audit` |
| Avaluar UX (jerarquia, càrrega cognitiva) | `/impeccable-critique` |
| Planificar disseny abans de codificar | `/impeccable-shape` |
| Pas final pre-lliurament | `/impeccable-polish` |
| Millorar tipografia | `/impeccable-typeset` |
| Afegir color a UI grisa | `/impeccable-colorize` |
| Afegir animacions | `/impeccable-animate` |
| UI massa genèrica/avorrida | `/impeccable-bolder` |
| UI massa carregada | `/impeccable-quieter` o `/impeccable-distill` |
| Adaptar a mòbil | `/impeccable-adapt` |
| Preparar per producció (errors, empty states) | `/impeccable-harden` |
| Millorar textos/microcopy | `/impeccable-clarify` |
| Impressionar (landing, demo) | `/impeccable-overdrive` |
| Afegir personalitat/joia | `/impeccable-delight` |
| Optimitzar performance UI | `/impeccable-optimize` |
| Escaneig automàtic anti-patrons | `npx impeccable detect .` (CLI) |
| Escanejar URL en producció | `npx impeccable detect https://miratfotos.com` |

#### Expect CLI — Testing automàtic en browser

**Quan:** Després de fer canvis que afecten la UI web.

| Situació | Command |
|----------|---------|
| Testar canvis recents (git diff) | `/expect` dins Claude Code |
| TUI interactiva | `expect-cli tui` |
| Test específic | `expect-cli tui -m "test the login flow" -y` |
| Amb URL concreta | `expect-cli tui -u http://localhost:3000 -m "test" -y` |
| Mode headless (CI) | `expect-cli tui --browser-mode headless -m "test"` |
| Watch mode (auto-rerun) | `expect-cli watch -m "test the login flow"` |
| Core Web Vitals | `expect-cli performance_metrics` |
| Auditoria accessibilitat | `expect-cli accessibility_audit` |
| Captura pantalla | `expect-cli screenshot` |

**Quan NO usar-lo:**
- Tests unitaris de lògica → usar `/tdd` (ECC)
- Tests d'API backend → usar `/tdd` o `/e2e` (ECC)

#### Graphify — Knowledge graph del codebase

**Quan:** A l'inici d'un projecte o quan el codebase és prou complex per perdre't.

| Situació | Command |
|----------|---------|
| Primer graf d'un projecte | `/graphify .` (dins el directori del projecte) |
| Extracció profunda | `/graphify . --mode deep` |
| Actualitzar després de canvis | `/graphify . --update` |
| Watch mode (auto-rebuild) | `/graphify . --watch` |
| Query directa al graf | `graphify query "com funciona X?"` |
| Mesurar estalvi tokens | `graphify benchmark` |
| Exportar a Obsidian | `/graphify . --obsidian` |
| Exportar SVG | `/graphify . --svg` |
| Instal·lar git hooks (auto-rebuild) | `graphify hook install` |

**Quan fer `/graphify .` per primer cop:**
- mirat → sí (60+ fitxers, multi-component)
- filmat → sí (pipeline complex)
- gestor-documental → sí (PDFs, email, signatures)
- bustia → sí (FastAPI + React + IMAP)
- organitzat → potser (més petit, menys complex)
- CartApp → no cal (iOS/Android, sense web complex)
- Satel·lit → potser (Python + FastAPI, relativament petit)

**Quan NO usar-lo:**
- Projectes amb <15 fitxers → no val la pena
- Edicions ràpides a un sol fitxer → no necessites el graf

### Combinació AIDesigner + Impeccable (workflow recomanat)

```
1. AIDesigner generate_design    → Primer draft HTML
2. /impeccable-critique          → Avaluar UX del draft
3. AIDesigner refine_design      → Iterar amb feedback de la critique
4. /impeccable-audit             → Auditoria tècnica (a11y, responsive)
5. AIDesigner refine_design      → Corregir problemes trobats
6. /impeccable-polish            → Pas final de detalls
7. npx impeccable detect .       → Validació automàtica anti-patrons
8. Integrar al projecte Next.js
```

## 1. Everything Claude Code (ECC)

**Repo:** https://github.com/affaan-m/everything-claude-code
**Versió:** v1.10.0 (152K stars, MIT license)
**Instal·lació:** `./install.sh python typescript swift` + 9 skills extres copiades manualment
**Ubicació:** `~/.claude/` (rules, agents, commands, skills)

### Què s'ha instal·lat

| Component | Quantitat | Ubicació |
|-----------|-----------|----------|
| Agents | 48 | `~/.claude/agents/` |
| Commands | 80 | `~/.claude/commands/` |
| Skills | 66 (57 base + 9 extres) | `~/.claude/skills/` |
| Rules | 89 fitxers .md (14 llenguatges) | `~/.claude/rules/` |

### Agents rellevants pels nostres projectes

| Agent | Ús previst |
|-------|-----------|
| planner | Planificar migracions Supabase→local, Vercel→Docker |
| architect | Redissenyar arquitectura local-first (FastAPI + SQLite/PostgreSQL + Docker) |
| python-reviewer | Revisar codi Python (pipelines IA, FastAPI, Gemma 4) |
| typescript-reviewer | Revisar codi Next.js (mirat, filmat, gestor-documental, organitzat) |
| database-reviewer | Validar esquemes i migracions de DB |
| security-reviewer | Auditoria seguretat — dades personals (fotos, emails, documents) en local |
| tdd-guide | Tests des del principi en les migracions |
| build-error-resolver | Errors Docker builds, dependències PyTorch/ONNX al M5 Max |
| performance-optimizer | Pipelines IA locals (5 models simultanis mirat, ffmpeg filmat) |
| refactor-cleaner | Netejar codi Supabase/Vercel residual post-migració |

### Skills extres copiades manualment (9)

| Skill | Descripció | Projectes que l'usen |
|-------|-----------|---------------------|
| docker-patterns | Contenidors, docker-compose, networking, volums | Tots (migració local) |
| security-review | Checklist seguretat: auth, secrets, input validation | Tots |
| security-scan | Escaneig vulnerabilitats config Claude Code (AgentShield) | Infraestructura |
| database-migrations | Migracions esquema PostgreSQL/SQLite, rollbacks, zero-downtime | mirat, gestor-documental, organitzat |
| postgres-patterns | Optimització queries, indexos, esquemes PostgreSQL | mirat, gestor-documental, organitzat |
| pytorch-patterns | Patrons deep learning, training pipelines, data loading | mirat (face detection), filmat (scene detection) |
| cost-aware-llm-pipeline | Routing Gemma 4 local vs Claude API, control de costos | Tots els que usen IA |
| agent-harness-construction | Dissenyar pipelines multi-model encadenats | mirat (pipeline 5 models), filmat |
| deployment-patterns | CI/CD, Docker, health checks, rollback | Tots (deploy local) |

### Commands més útils

| Command | Descripció |
|---------|-----------|
| `/plan` | Planificar implementació abans de tocar codi |
| `/code-review` | Revisió automàtica de canvis |
| `/tdd` | Cicle test-driven development |
| `/build-fix` | Resoldre errors de build |
| `/security-review` | Auditoria seguretat sota demanda |
| `/e2e` | Tests end-to-end |
| `/verify` | Verificació final post-canvi |
| `/refactor-clean` | Netejar codi obsolet |

### Skills que NO hem instal·lat (per ara)

- SEO, content-engine, brand-voice, market-research → **Fase 2** quan llancem mirat/arxivat al mercat
- Go, Rust, Java, Kotlin, C++, Perl, PHP, Laravel, Spring Boot, Flutter → No usat als projectes
- Healthcare/HIPAA/DeFi compliance → No aplica
- GAN planner/generator → No fem generació d'imatges amb GANs

### Notes

- Les rules s'instal·len per TOTS els llenguatges (14) malgrat filtrar per python/typescript/swift — és el comportament per defecte d'ECC. Les rules d'altres llenguatges no afecten el rendiment.
- El repo clonat es queda a `/Users/enric/Projectes/everything-claude-code/` per si cal actualitzar o copiar més skills en el futur.

---

## 2. Impeccable

**Repo:** https://github.com/pbakaus/impeccable
**Versió:** v2.1.7 (Apache 2.0)
**Instal·lació:** Skills copiades manualment a `~/.claude/skills/impeccable-*/` (global)
**CLI:** `npx impeccable detect [path|url]`
**Combinat amb:** AIDesigner.ai (MCP server connectat) per generar + refinar UI

### Què fa

Sistema de qualitat de disseny frontend que guia Claude Code cap a UI d'alta qualitat, evitant "AI slop" (els patrons genèrics que delaten que una UI l'ha fet una IA).

### 18 Skills instal·lades

| Skill | Descripció | Quan usar |
|-------|-----------|-----------|
| `impeccable-impeccable` | Skill principal: genera UI distintiva, production-grade | Crear qualsevol component/pàgina nova |
| `impeccable-shape` | Planificació UX/UI abans de codificar | Fase de disseny, abans d'implementar |
| `impeccable-audit` | Auditoria tècnica: a11y, performance, responsive, anti-patrons | Revisió de qualitat pre-llançament |
| `impeccable-critique` | Avaluació UX: jerarquia, arquitectura info, càrrega cognitiva | Revisió de disseny |
| `impeccable-polish` | Pas final: alineació, spacing, consistència, micro-detalls | Últim pas abans de lliurar |
| `impeccable-layout` | Millorar layout, spacing, ritme visual | Quan el layout no queda bé |
| `impeccable-typeset` | Tipografia: fonts, jerarquia, mida, pes, llegibilitat | Quan el text no es veu professional |
| `impeccable-colorize` | Afegir color estratègic a UI monocromàtiques | UI massa grises o avorrides |
| `impeccable-animate` | Animacions i micro-interaccions amb propòsit | Afegir moviment i feedback visual |
| `impeccable-bolder` | Amplificar dissenys massa conservadors | Quan la UI és massa genèrica |
| `impeccable-quieter` | Reduir dissenys massa agressius/sobreestimulants | Quan la UI és massa carregada |
| `impeccable-distill` | Simplificar eliminant complexitat innecessària | Quan la UI té massa elements |
| `impeccable-delight` | Afegir moments de joia i personalitat | Per fer la UI memorable |
| `impeccable-overdrive` | Implementacions ambicioses: shaders, spring physics, scroll-driven | Per impressionar, demos, landing pages |
| `impeccable-harden` | Production-ready: errors, empty states, i18n, edge cases | Preparar per producció |
| `impeccable-clarify` | Millorar UX copy, missatges d'error, microcopy | Textos confusos o poc clars |
| `impeccable-adapt` | Responsivitat: breakpoints, fluid layouts, touch targets | Adaptar a mòbil/tablet |
| `impeccable-optimize` | Performance UI: rendering, animacions, bundle size | UI lenta o amb jank |

### CLI detector d'anti-patrons

```bash
npx impeccable detect .                    # Escanejar directori
npx impeccable detect index.html           # Escanejar fitxer
npx impeccable detect https://miratfotos.com  # Escanejar URL
npx impeccable detect --fast --json .      # Mode ràpid, output JSON
```

Detecta 24 problemes:
- **AI slop:** gradients morats, bounce easing, dark glows, Inter/Arial per defecte
- **Qualitat:** línies llargues, padding estret, touch targets petits, headings saltats, contrast baix

### Workflow recomanat amb AIDesigner

1. **AIDesigner** genera/refina el disseny inicial (MCP: `generate_design` / `refine_design`)
2. **Impeccable** audita i poleix el resultat:
   - `/audit` → trobar problemes tècnics
   - `/critique` → avaluar UX
   - `/polish` → pas final de qualitat
3. `npx impeccable detect` → escaneig automàtic anti-patrons

### Projectes que l'usaran

- **mirat** — UI web de galeria de fotos (Next.js)
- **filmat** — Dashboard de producció de vídeo (Next.js)
- **gestor-documental** — Interfície de gestió documental (Next.js)
- **organitzat** — App de productivitat (Next.js + iOS)
- **Qualsevol projecte nou amb UI**

---

## 3. Expect CLI

**Repo:** https://github.com/millionco/expect
**Web:** https://expect.dev
**Versió:** v0.1.3 (FSL-1.1-MIT)
**Instal·lació:** `npm install -g expect-cli` + MCP server configurat a `~/.claude.json`
**CLI:** `expect-cli` o `npx expect-cli`

### Què fa

Eina de testing automàtic que llegeix els canvis de git, genera un test plan amb IA, i l'executa en un browser real (Playwright). No cal escriure tests manualment.

### Com funciona

1. Fas canvis al codi (git diff)
2. Executes `/expect` dins Claude Code (o `expect-cli tui`)
3. Llegeix el diff, genera test plan automàticament
4. Aproves el pla (TUI interactiva)
5. Executa tests en browser real amb Playwright
6. Retorna pass/fail + gravació de sessió

### Què testa

| Categoria | Què detecta |
|-----------|------------|
| Performance | Long animation frames, INP, LCP (Core Web Vitals) |
| Security | npm deps vulnerables, CSRF attacks |
| Design | Hover states trencats, links/botons no funcionals |
| Completeness | Metadata faltant, dead links |
| Accessibility | Auditoria WCAG |

### Commands principals

```bash
expect-cli tui                                    # TUI interactiva
expect-cli tui -m "test the login flow" -y        # Executar directament
expect-cli tui --browser-mode headless -m "test"  # Mode headless
expect-cli tui -u http://localhost:3000 -m "test" # Especificar URL
expect-cli watch -m "test the login flow"         # Watch mode (auto-rerun)
expect-cli performance_metrics                    # Core Web Vitals
expect-cli accessibility_audit                    # Auditoria WCAG
expect-cli screenshot                             # Captura pantalla
```

### Integració

- **MCP server** configurat globalment a `~/.claude.json` → disponible a totes les sessions Claude Code
- **CI/CD:** `--ci` flag per GitHub Actions (headless, no cookies, auto-approve, timeout 30min)
- Compatible amb: Claude Code, Cursor, Codex, Gemini CLI

### Workflow combinat

| Fase | Eina | Acció |
|------|------|-------|
| 1. Tests unitaris/integració | TDD (tdd-guide) | Tests de lògica i API |
| 2. Testing visual en browser | **Expect CLI** | Tests funcionals automàtics des del diff |
| 3. Auditoria disseny | Impeccable | Qualitat visual i anti-patrons |
| 4. Performance check | Expect + Impeccable | CWV + bundle size |

### Projectes que l'usaran

Tots els que tenen UI web amb Next.js: mirat, filmat, gestor-documental, organitzat, i nous projectes.

---

## 4. Graphify

**Repo:** https://github.com/safishamsi/graphify
**Versió:** v0.4.6 (MIT)
**Instal·lació:** `pipx install graphifyy` + `graphify install --platform claude`
**CLI:** `graphify` (via pipx, a `~/.local/bin/`)
**Skill:** `~/.claude/skills/graphify/SKILL.md` → `/graphify` dins Claude Code

### Què fa

Transforma qualsevol carpeta (codi, docs, PDFs, imatges, vídeos) en un **knowledge graph** queryable. Claude Code consulta el graf abans de buscar fitxers, estalviant ~71x tokens per query.

### Com funciona

1. **Extracció AST** determinista via tree-sitter (22 llenguatges) — sense LLM
2. **Whisper local** per transcriure media (vídeos/àudio) — resultats cached
3. **Claude subagents en paral·lel** per extracció semàntica (docs, PDFs, imatges)
4. **Leiden community detection** per clustering — sense vector DB

### Output

| Fitxer | Descripció |
|--------|-----------|
| `graphify-out/graph.json` | Graf persistent per queries |
| `graphify-out/GRAPH_REPORT.md` | God nodes, comunitats, connexions sorprenents |
| `graphify-out/graph.html` | Visualització interactiva del graf |
| Cache SHA256 | Actualitzacions incrementals (només fitxers nous/canviats) |

### Commands principals

```bash
/graphify .                          # Pipeline complet directori actual
/graphify /path --mode deep          # Extracció profunda
/graphify /path --update             # Incremental (només nous/canviats)
/graphify /path --watch              # Auto-rebuild on changes (sense LLM)
/graphify /path --obsidian           # Exportar a vault Obsidian
/graphify /path --neo4j              # Generar Cypher per Neo4j
/graphify /path --svg                # Exportar SVG (GitHub, Notion)
graphify query "com funciona el face detection?"  # Query directa al graf
graphify benchmark                   # Mesurar reducció tokens vs naive
```

### Integració Claude Code

- **PreToolUse hook** → Claude consulta `GRAPH_REPORT.md` abans de cada file-search
- **Skill** → `/graphify` disponible com a command
- **Git hooks** opcionals: `graphify hook install` → post-commit/post-checkout auto-rebuild

### Tipus de fitxers suportats

| Tipus | Processing |
|-------|-----------|
| Codi (.py, .ts, .js, .go, .rs, .java, .c/cpp + 14 més) | AST + call graphs |
| Docs (.md, .txt, .rst) | Extracció semàntica Claude |
| Papers (.pdf) | Citation mining |
| Imatges (.png, .jpg, .webp) | Vision-based extraction |
| Media (.mp4, .mp3, .wav) | Whisper transcripció local |

### Projectes candidats

| Projecte | Per què és bon candidat |
|----------|----------------------|
| **mirat** | 60+ fitxers Next.js + Python pipeline + face-service + docs. Graf connecta models IA ↔ API routes ↔ components ↔ BD |
| **filmat** | Pipeline complex: ffmpeg, whisperx, scene detection, front. Graf mapeja tot el flux |
| **gestor-documental** | PDFs, email, OCR, signatures — graf mostra dependències |
| **bustia** | FastAPI + React + SQLite + IMAP — graf connecta backend ↔ frontend ↔ email |

### Notes

- L'extracció semàntica (pas 3) **consumeix tokens de Claude API** — no és gratis per docs/PDFs/imatges
- L'extracció AST de codi (pas 1) és **gratuïta** — tree-sitter local, sense LLM
- S'executa **per projecte** (`/graphify .` dins cada repo), no globalment
- El `--watch` mode no usa LLM — ideal per mantenir el graf actualitzat durant desenvolupament
- El `--update` mode només re-processa fitxers canviats — eficient per projectes grans
- `pipx` instal·lat via brew com a dependència (gestor de CLI tools Python isolats)

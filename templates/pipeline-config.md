# Pipeline Config

このファイルは対象プロジェクトの `docs/pipeline-config.md` にコピーして使う。dev-pipeline のオーケストレーターが実行開始時にこれを読み、`## stack` を全フェーズのサブエージェントに、各フェーズ節（`## design` など）を対応するフェーズのサブエージェントにそのまま渡す。ここに書いた内容はデフォルト扱いであり、実リポジトリの規約・実装が常に優先される。以下は Vue 3 + Spring Boot スタックの例 — 対象プロジェクトに合わせて書き換えること。

## stack

SPA with a Vue 3 + TypeScript + Pinia + Vuetify + Vite + pnpm frontend and a Java Spring Boot + Flyway + PostgreSQL backend, developed inside a devcontainer. Build/test commands must be discovered from the repo (package.json scripts, mvnw/gradlew wrapper), not guessed; if a needed tool is missing, report it — don't install it.

## requirements

- For a full-stack change, name the affected layers explicitly: UI components / frontend state (Pinia stores) / API client / backend API / backend service logic / DB schema.
- When both frontend and backend behavior change, write separate acceptance criteria for the API behavior and the UI behavior rather than one merged criterion.

## design

- If the change crosses the frontend/backend boundary, the design MUST pin the API contract before anything else: endpoint path + HTTP method, request/response shapes (field names, types, nullability — concrete enough to write both the Java DTO and the TypeScript type from), and error responses.
- DB schema changes are expressed as new Flyway migrations only (`V<next>__<description>.sql` in the migration directory the repo already uses). Never plan an edit to an already-applied migration.
- Sequence steps in dependency order: Flyway migration → backend (entity/repository/service/controller) → frontend (API client → Pinia store/composables → UI components). Each step must leave the repo compiling.
- Respect the repo's existing layering on both sides (controller/service/repository; components/composables/stores) and name the concrete files — don't leave the implementer to invent placement.

## implementation

- Frontend: use `<script setup lang="ts">` SFCs; keep shared state in Pinia stores and use `storeToRefs` when destructuring reactive store state; prefer Vuetify components and props over hand-rolled CSS; never introduce `any` or `as` casts to silence type errors — fix the types.
- Backend: constructor injection (no field `@Autowired`); transaction boundaries (`@Transactional`) at the service layer; don't return JPA entities from controllers — use the repo's DTO pattern; validate request input the way the repo already does (`@Valid` etc.).
- DB: schema changes only as a new Flyway migration (`V<next>__<description>.sql`); never modify an already-applied migration file.
- Verification: typically typecheck (`vue-tsc`) + lint for frontend changes, compile (`./mvnw compile` or gradle equivalent) for backend changes.

## testing

- Frontend: Vitest, with @vue/test-utils or Testing Library per repo convention, for components; Pinia stores can be tested directly (`setActivePinia(createPinia())`) without mounting a component.
- Backend: JUnit 5; prefer the narrowest Spring test slice that proves the criterion (`@WebMvcTest` for controllers, `@DataJpaTest` for repositories, full `@SpringBootTest` only when the criterion genuinely spans layers); use Testcontainers for PostgreSQL if the repo already does.
- If a Flyway migration was added, confirm it applies cleanly — a backend test run against a fresh database usually proves this; if migrations fail to apply, that is a test failure.

## review

- Frontend: reactivity loss (destructuring a Pinia store or reactive object without `storeToRefs`/`toRefs`), missing `await` on a promise whose result or error matters, watchers/intervals/listeners registered without cleanup, `v-for` without a stable `:key`, state mutated outside its Pinia store, `any`/`as` casts papering over a real type mismatch.
- Backend: N+1 queries (lazy relations accessed in loops or during serialization), missing or misplaced `@Transactional` (multi-write operations without one; one on a read-only path hiding a write), JPA entities returned directly from controllers, string-concatenated SQL/JPQL, new endpoints without input validation, error responses leaking stack traces or internals.
- DB: any edit to an already-applied Flyway migration (checksum break on deploy), migration content not matching the entity changes.
- Dependencies: `package.json` changed without a matching `pnpm-lock.yaml` change (or vice versa).

## publish

- If `package.json` changed, `pnpm-lock.yaml` must be committed with it (and vice versa).
- If the change includes Flyway migration files, call them out explicitly in the PR body — they alter the database schema on deploy and reviewers must see them.

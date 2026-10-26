# VideoResume

VideoResume es una app SwiftUI para iPhone, iPad y Mac que:

1. Busca una playlist pública de YouTube (por defecto, `resume`).
2. Detecta los vídeos todavía no procesados.
3. Intenta obtener sus subtítulos públicos; si no existen, usa el título y la descripción.
4. Envía el contenido a un modelo de OpenRouter con un prompt configurable.
5. Guarda localmente qué vídeos ya se resumieron y prepara un email con los nuevos resúmenes.

## Abrir y ejecutar

Abre `VideoResume.xcodeproj` con Xcode, selecciona el destino **VideoResume** para macOS o iOS y pulsa Run.

Antes del primer uso, abre Ajustes e introduce:

- API key de YouTube Data API v3.
- `@handle` o ID del canal y el nombre de la playlist, o directamente el ID de la playlist.
- Email destinatario.
- API key de OpenRouter y modelo.
- Prompt para el resumen.

Las claves se guardan en el Keychain del dispositivo. El resto de ajustes y el historial se guardan localmente.

## Límites importantes del MVP

- Una API key solo puede leer playlists públicas. Para playlists privadas se necesita implementar OAuth de Google.
- YouTube Data API no ofrece transcripciones públicas con una API key. La app intenta el endpoint público de subtítulos y usa título/descripción como alternativa.
- iOS y macOS obligan a que el usuario confirme el envío en Mail. El envío totalmente automático requiere un backend o un proveedor transaccional (por ejemplo, Resend/SendGrid).
- El historial es local a cada dispositivo. Para evitar duplicados entre iPhone y Mac habría que activar CloudKit/iCloud con la cuenta de desarrollador del proyecto.

## Seguridad

No subas claves al repositorio. VideoResume no escribe las claves en archivos ni en `UserDefaults`; utiliza Keychain.

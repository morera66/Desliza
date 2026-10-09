# Desliza: limpiador de fotos tipo Favvy (iPhone, sin Mac)

App nativa en SwiftUI para iOS 17 o superior. La compila GitHub en un Mac en la nube y tú la instalas desde Windows con Sideloadly.

## 1. Compilar en GitHub (una vez y cada vez que cambies el código)
1. Crea un repositorio nuevo en github.com (por ejemplo `desliza`). Si es **público**, los minutos de compilación son gratis e ilimitados. Si es privado también funciona, pero gasta de tu cuota gratuita (de sobra para esto).
2. *Add file > Upload files* y arrastra **todo el contenido** de esta carpeta: `Desliza/`, `.github/`, `project.yml` y este LEEME. Comprueba que se sube la carpeta `.github`. Pulsa *Commit*.
3. Ve a la pestaña **Actions**. Verás "Compilar IPA" en marcha (tarda unos 5 min).
   - Si sale en **verde**: entra en la ejecución y, abajo, en *Artifacts*, descarga **Desliza-ipa**. Descomprímelo y tendrás `Desliza.ipa`.
   - Si sale en **rojo**: abre el paso que ha fallado, copia las líneas con `error:` y pásamelas.

## 2. Instalar en el iPhone desde Windows
1. Instala **iTunes** e **iCloud** descargados de la web de Apple (no los de Microsoft Store). Sideloadly los necesita para ver el iPhone.
2. Descarga e instala **Sideloadly** desde sideloadly.io.
3. Conecta el iPhone por cable y pulsa *Confiar en este ordenador*.
4. En Sideloadly, arrastra `Desliza.ipa`, escribe tu Apple ID y pulsa **Start**. Usa un Apple ID secundario si prefieres no poner el principal.
5. En el iPhone:
   - *Ajustes > Privacidad y seguridad > Modo de desarrollador*: actívalo (se reinicia).
   - *Ajustes > General > VPN y gestión de dispositivos*: confía en tu Apple ID.
6. Abre Desliza y concede **acceso total** a las fotos.

> Con Apple ID gratuito la app caduca a los **7 días**. Para renovarla, vuelve a pasar el mismo .ipa con Sideloadly (no pierdes el progreso). Sideloadly también puede refrescarla sola por WiFi si el PC está encendido.

## Qué hace
- **Deslizar**: izquierda papelera, derecha conservar. Botón de deshacer. Si tocas la foto, la ves a pantalla completa y los vídeos se reproducen.
- **Iterativo**: lo que conservas no vuelve a salir y el progreso se guarda.
- **Categorías**: Recientes, Aleatorias, Este día, Capturas, Vídeos y Por mes.
- **Liberar mucho espacio**: Vídeos más pesados y Duplicados/casi idénticas.
- **Papelera propia** con borrado en bloque y contador de espacio liberado.

## Notas
- Lo borrado pasa 30 días en **Eliminados recientemente** de Fotos. Si quieres el espacio ya, vacía ese álbum.
- Las fotos que solo están en iCloud tardan más en cargar, y el buscador de duplicados se las salta.

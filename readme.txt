Voici l’addon Windower 4 AddonManager.lua : une fenêtre cliquable qui liste tes addons et tes plugins.

Installation

Place le fichier dans Windower4/addons/AddonManager/AddonManager.lua.
En jeu, tape //lua load addonmanager. Pour qu’il se charge tout seul, ajoute cette ligne dans scripts/init.txt.

Utilisation

Les onglets Addons et Plugins affichent les dossiers addons/ et plugins/ (fichiers .dll). Les entrées sont marquées ON (vert) ou OFF (rouge).
Clic gauche sur une ligne : charge ou décharge. Un addon passe par lua load/unload, un plugin par load/unload.
Clic droit sur un addon : lua reload.
La molette et les boutons < > changent de page. Le bouton Refresh rescanne les dossiers.
Tu peux déplacer la fenêtre en faisant glisser la barre du haut. Le X la ferme.
 Commandes    : //am            afficher / cacher la fenetre
                   //am collapse   replier / deplier la fenetre
                   //am filter x   filtrer la liste (//am filter pour effacer)
                   //am refresh    rescanner les dossiers addons / plugins
                   //am reset      relire l'autoload (scripts/init.txt, scripts/autoload, exec) et recalculer l'etat
                   //am debug      afficher les fichiers d'autoload lus et les lignes non reconnues
                   //am mouse      afficher les codes d'evenements souris (diagnostic clic droit)
                   //am sc         lister les shortcuts
                   //am sc add <nom> = <commande>
                   //am sc edit <n> [<nom> =] <commande>
                   //am sc del <n> | move <n> <pos> | run <n> | reload
                   Les shortcuts sont dans addons/AddonManager/data/shortcuts.txt (une ligne : nom|commande),
                   modifiable aussi a la main puis //am sc reload.
                   //am pos x y    deplacer la fenetre
    Onglets      : Addons / Plugins / Shortcuts (raccourcis de commandes editables)
    Souris       : clic gauche sur une ligne = load / unload
                   clic droit sur un addon    = reload ; sur un shortcut = l'editer
                   bouton [-] / [+] de la barre du haut (ou clic droit sur la barre) = replier / deplier
                   molette = changer de page, barre du haut = deplacer
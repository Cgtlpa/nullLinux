package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

type App struct {
	Method string
	Target string
}

var registry = map[string]App{
	"firefox":                   {"flatpak", "org.mozilla.firefox"},
	"google-chrome":             {"flatpak", "com.google.Chrome"},
	"chromium":                  {"flatpak", "org.chromium.Chromium"},
	"brave-browser":             {"flatpak", "com.brave.Browser"},
	"librewolf":                 {"flatpak", "io.gitlab.librewolf-community"},
	"thunderbird":               {"flatpak", "org.mozilla.Thunderbird"},
	"evolution":                 {"flatpak", "org.gnome.Evolution"},
	"slack":                     {"flatpak", "com.slack.Slack"},
	"discord":                   {"flatpak", "com.discordapp.Discord"},
	"telegram-desktop":          {"flatpak", "org.telegram.desktop"},
	"element-desktop":           {"flatpak", "im.riot.Riot"},
	"transmission-gtk":          {"flatpak", "com.transmissionbt.Transmission"},
	"qbittorrent":               {"flatpak", "org.qbittorrent.qBittorrent"},
	"remmina":                   {"flatpak", "org.remmina.Remmina"},
	"openssh-server":            {"system", "openssh-server"},
	"nautilus":                  {"system", "nautilus"},
	"dolphin":                   {"system", "dolphin"},
	"thunar":                    {"system", "thunar"},
	"ranger":                    {"system", "ranger"},
	"mc":                        {"system", "mc"},
	"synaptic":                  {"system", "synaptic"},
	"gnome-software":            {"system", "gnome-software"},
	"discover":                  {"system", "discover"},
	"gparted":                   {"system", "gparted"},
	"gnome-disk-utility":        {"system", "gnome-disk-utility"},
	"timeshift":                 {"system", "timeshift"},
	"baobab":                    {"system", "baobab"},
	"bleachbit":                 {"system", "bleachbit"},
	"stacer":                    {"system", "stacer"},
	"htop":                      {"system", "htop"},
	"libreoffice":               {"flatpak", "org.libreoffice.LibreOffice"},
	"onlyoffice-desktopeditors": {"flatpak", "org.onlyoffice.desktopeditors"},
	"wps-office":                {"flatpak", "com.wps.Office"},
	"scribus":                   {"flatpak", "net.scribus.Scribus"},
	"obsidian":                  {"flatpak", "md.obsidian.Obsidian"},
	"joplin":                    {"flatpak", "net.cozic.joplin_desktop"},
	"cherrytree":                {"flatpak", "net.giuspen.cherrytree"},
	"logseq":                    {"flatpak", "com.logseq.Logseq"},
	"typora":                    {"flatpak", "io.typora.Typora"},
	"ghostwriter":               {"flatpak", "io.github.wereturtle.ghostwriter"},
	"zotero":                    {"flatpak", "org.zotero.Zotero"},
	"calibre":                   {"flatpak", "com.calibre_ebook.calibre"},
	"okular":                    {"flatpak", "org.kde.okular"},
	"evince":                    {"flatpak", "org.gnome.Evince"},
	"xreader":                   {"system", "xreader"},
	"gimp":                      {"flatpak", "org.gimp.GIMP"},
	"inkscape":                  {"flatpak", "org.inkscape.Inkscape"},
	"krita":                     {"flatpak", "org.kde.krita"},
	"darktable":                 {"flatpak", "org.darktable.Darktable"},
	"rawtherapee":               {"flatpak", "com.rawtherapee.RawTherapee"},
	"shotwell":                  {"flatpak", "org.gnome.Shotwell"},
	"digikam":                   {"flatpak", "org.kde.digikam"},
	"blender":                   {"flatpak", "org.blender.Blender"},
	"audacity":                  {"flatpak", "org.audacityteam.Audacity"},
	"ardour":                    {"flatpak", "org.ardour.Ardour"},
	"lmms":                      {"flatpak", "io.lmms.LMMS"},
	"obs-studio":                {"flatpak", "com.obsproject.Studio"},
	"kdenlive":                  {"flatpak", "org.kde.kdenlive"},
	"openshot":                  {"flatpak", "org.openshot.OpenShot"},
	"handbrake":                 {"flatpak", "fr.handbrake.ghb"},
	"vscode":                    {"flatpak", "com.visualstudio.code"},
	"code-oss":                  {"system", "code"},
	"vim":                       {"system", "vim"},
	"neovim":                    {"system", "neovim"},
	"emacs":                     {"system", "emacs"},
	"sublime-text":              {"flatpak", "com.sublimetext.three"},
	"atom":                      {"system", "atom"},
	"git":                       {"system", "git"},
	"gitkraken":                 {"flatpak", "com.axosoft.GitKraken"},
	"github-desktop":            {"flatpak", "io.github.shiftey.Desktop"},
	"docker":                    {"system", "docker.io"},
	"virtualbox":                {"system", "virtualbox"},
	"gnome-builder":             {"flatpak", "org.gnome.Builder"},
	"qtcreator":                 {"flatpak", "io.qt.QtCreator"},
	"postman":                   {"flatpak", "com.getpostman.Postman"},
	"vlc":                       {"flatpak", "org.videolan.VLC"},
	"mpv":                       {"flatpak", "io.mpv.Mpv"},
	"smplayer":                  {"flatpak", "info.smplayer.SMPlayer"},
	"rhythmbox":                 {"flatpak", "org.gnome.Rhythmbox3"},
	"clementine":                {"flatpak", "org.clementine_player.Clementine"},
	"strawberry":                {"flatpak", "org.strawberrymusicplayer.strawberry"},
	"spotify-client":            {"flatpak", "com.spotify.Client"},
	"celluloid":                 {"flatpak", "io.github.celluloid_player.Celluloid"},
	"kodi":                      {"flatpak", "tv.kodi.Kodi"},
	"audacious":                 {"flatpak", "org.atheme.audacious"},
	"deadbeef":                  {"flatpak", "io.github.DeaDBeeF"},
	"picard":                    {"flatpak", "org.musicbrainz.Picard"},
	"sound-juicer":              {"system", "sound-juicer"},
	"asunder":                   {"system", "asunder"},
	"gnome-terminal":            {"system", "gnome-terminal"},
	"konsole":                   {"system", "konsole"},
	"tilix":                     {"system", "tilix"},
	"alacritty":                 {"system", "alacritty"},
	"kitty":                     {"system", "kitty"},
	"synapse":                   {"system", "synapse"},
	"rofi":                      {"system", "rofi"},
	"dmenu":                     {"system", "dmenu"},
	"flameshot":                 {"system", "flameshot"},
	"shutter":                   {"system", "shutter"},
	"peek":                      {"flatpak", "com.uploadedlobster.peek"},
	"kazam":                     {"system", "kazam"},
	"gufw":                      {"system", "gufw"},
	"redshift":                  {"system", "redshift"},
	"variety":                   {"system", "variety"},
	"gnome-shell":               {"system", "gnome-shell"},
	"kde-plasma-desktop":        {"system", "kde-plasma-desktop"},
	"xfce4":                     {"system", "xfce4"},
	"cinnamon":                  {"system", "cinnamon"},
	"i3-wm":                     {"system", "i3-wm"},
	"clamav":                    {"system", "clamav"},
	"rkhunter":                  {"system", "rkhunter"},
	"lynis":                     {"system", "lynis"},
	"keepassxc":                 {"flatpak", "org.keepassxc.KeePassXC"},
	"bitwarden":                 {"flatpak", "com.bitwarden.desktop"},
	"veracrypt":                 {"system", "veracrypt"},
	"gpg":                       {"system", "gpg"},
	"torbrowser-launcher":       {"flatpak", "com.github.micahflee.torbrowser-launcher"},
	"protonvpn":                 {"flatpak", "com.protonvpn.www"},
	"wireguard-tools":           {"system", "wireguard-tools"},
	"snapd":                     {"system", "snapd"},
	"flatpak":                   {"system", "flatpak"},
	"nala":                      {"system", "nala"},
	"aptitude":                  {"system", "aptitude"},
	"yay":                       {"system", "yay"},
	"curl":                      {"system", "curl"},
	"wget":                      {"system", "wget"},
	"neofetch":                  {"system", "neofetch"},
	"tree":                      {"system", "tree"},
	"jq":                        {"system", "jq"},
	"ripgrep":                   {"system", "ripgrep"},
	"fd":                        {"system", "fd-find"},
	"bat":                       {"system", "bat"},
	"exa":                       {"system", "exa"},
	"eza":                       {"system", "eza"},
	"tmux":                      {"system", "tmux"},
	"zsh":                       {"system", "zsh"},
	"fish":                      {"system", "fish"},
	"nano":                      {"system", "nano"},
	"micro":                     {"system", "micro"},
	"rsync":                     {"system", "rsync"},
	"ffmpeg":                    {"system", "ffmpeg"},
	"youtube-dl":                {"system", "youtube-dl"},
	"yt-dlp":                    {"system", "yt-dlp"},
	"imagemagick":               {"system", "imagemagick"},
	"fzf":                       {"system", "fzf"},
	"tldr":                      {"system", "tldr"},
	"ncdu":                      {"system", "ncdu"},
	"btop":                      {"system", "btop"},
	"duf":                       {"system", "duf"},
	"procs":                     {"system", "procs"},
	"dust":                      {"system", "dust"},
	"roblox":                    {"flatpak", "org.vinegarhq.Vinegar"},
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: null <install|search|update> [query]")
		os.Exit(1)
	}

	command := os.Args[1]

	if command == "search" {
		if len(os.Args) < 3 {
			fmt.Println("Usage: null search <query>")
			os.Exit(1)
		}
		searchQuery := strings.ToLower(os.Args[2])
		searchRegistry(searchQuery)
		return
	}

	if command == "install" {
		if len(os.Args) < 3 {
			fmt.Println("Usage: null install <packagename>")
			os.Exit(1)
		}
		packageName := strings.ToLower(os.Args[2])
		installPackage(packageName)
		return
	}

	if command == "update" {
		if len(os.Args) == 2 {
			updateAll()
		} else {
			packageName := strings.ToLower(os.Args[2])
			updatePackage(packageName)
		}
		return
	}

	fmt.Printf("Unknown command: %s\n", command)
	os.Exit(1)
}

func searchRegistry(query string) {
	fmt.Printf("Searching for '%s'...\n", query)
	found := false
	for name, app := range registry {
		if strings.Contains(name, query) || strings.Contains(strings.ToLower(app.Target), query) {
			fmt.Printf("- %s (Method: %s, Target: %s)\n", name, app.Method, app.Target)
			found = true
		}
	}
	if !found {
		fmt.Println("No matching packages found.")
	}
}

func installPackage(packageName string) {
	app, exists := registry[packageName]
	if !exists {
		fmt.Printf("Error: Package '%s' not found.\n", packageName)
		os.Exit(1)
	}

	fmt.Printf("Installing %s via %s...\n", packageName, app.Method)

	var err error
	if app.Method == "flatpak" {
		err = installFlatpak(app.Target)
	} else if app.Method == "system" {
		err = installSystemPackage(app.Target)
	}

	if err != nil {
		fmt.Printf("Failed to install %s: %v\n", packageName, err)
		os.Exit(1)
	}

	fmt.Printf("Successfully installed %s!\n", packageName)
}

func installFlatpak(target string) error {
	cmd := exec.Command("flatpak", "install", "-y", "flathub", target)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func installSystemPackage(target string) error {
	var pkgManager string
	var args []string

	if _, err := exec.LookPath("apt-get"); err == nil {
		pkgManager = "apt-get"
		args = []string{"install", "-y", target}
	} else if _, err := exec.LookPath("dnf"); err == nil {
		pkgManager = "dnf"
		args = []string{"install", "-y", target}
	} else if _, err := exec.LookPath("pacman"); err == nil {
		pkgManager = "pacman"
		args = []string{"-S", "--noconfirm", target}
	} else {
		return fmt.Errorf("no supported system package manager found")
	}

	cmd := exec.Command(pkgManager, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func updateAll() {
	fmt.Println("Updating all system packages...")
	var sysCmd *exec.Cmd

	if _, err := exec.LookPath("apt-get"); err == nil {
		updateCmd := exec.Command("apt-get", "update")
		updateCmd.Stdout = os.Stdout
		updateCmd.Stderr = os.Stderr
		updateCmd.Run()
		sysCmd = exec.Command("apt-get", "upgrade", "-y")
	} else if _, err := exec.LookPath("dnf"); err == nil {
		sysCmd = exec.Command("dnf", "upgrade", "-y")
	} else if _, err := exec.LookPath("pacman"); err == nil {
		sysCmd = exec.Command("pacman", "-Syu", "--noconfirm")
	}

	if sysCmd != nil {
		sysCmd.Stdout = os.Stdout
		sysCmd.Stderr = os.Stderr
		sysCmd.Run()
	}

	fmt.Println("Updating all Flatpak packages...")
	flatCmd := exec.Command("flatpak", "update", "-y")
	flatCmd.Stdout = os.Stdout
	flatCmd.Stderr = os.Stderr
	flatCmd.Run()

	fmt.Println("System update complete!")
}

func updatePackage(packageName string) {
	app, exists := registry[packageName]
	if !exists {
		fmt.Printf("Error: Package '%s' not found.\n", packageName)
		os.Exit(1)
	}

	fmt.Printf("Updating %s via %s...\n", packageName, app.Method)

	var err error
	if app.Method == "flatpak" {
		cmd := exec.Command("flatpak", "update", "-y", app.Target)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		err = cmd.Run()
	} else if app.Method == "system" {
		var sysCmd *exec.Cmd
		if _, e := exec.LookPath("apt-get"); e == nil {
			sysCmd = exec.Command("apt-get", "install", "--only-upgrade", "-y", app.Target)
		} else if _, e := exec.LookPath("dnf"); e == nil {
			sysCmd = exec.Command("dnf", "upgrade", "-y", app.Target)
		} else if _, e := exec.LookPath("pacman"); e == nil {
			sysCmd = exec.Command("pacman", "-S", "--noconfirm", app.Target)
		}

		if sysCmd != nil {
			sysCmd.Stdout = os.Stdout
			sysCmd.Stderr = os.Stderr
			err = sysCmd.Run()
		} else {
			err = fmt.Errorf("no supported system package manager found")
		}
	}

	if err != nil {
		fmt.Printf("Failed to update %s: %v\n", packageName, err)
		os.Exit(1)
	}

	fmt.Printf("Successfully updated %s!\n", packageName)
}

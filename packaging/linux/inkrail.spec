# Repackages the portable archive built by assemble.sh; nothing is compiled here.
%global debug_package %{nil}
# The host is a .NET single-file bundle: stripping it would corrupt the bundle.
%global __strip /bin/true
%global __brp_strip %{nil}
%global __brp_strip_comment_note %{nil}
%global __brp_strip_static_archive %{nil}
%global _build_id_links none

Name:           inkrail
Version:        %{version}
Release:        1%{?dist}
Summary:        Paper, ink, and a little room to write
License:        MIT AND OFL-1.1
URL:            https://github.com/Aaryanverma/inkrail
Source0:        Inkrail-Linux-%{archive_arch}.tar.gz
ExclusiveArch:  x86_64 aarch64

# Loaded at run time through P/Invoke, so rpm cannot discover them itself.
Requires:       gtk3
Requires:       webkit2gtk4.1
Requires:       hicolor-icon-theme
Recommends:     gstreamer1-plugins-good

%description
Inkrail is a quiet typewriter-style writing desk: paper, ink, typewriter
sounds, wax seals, Markdown import and export, and PDF letters. Letters are
stored as plain files in ~/.local/share/Inkrail and use the same library
format as Inkrail for Windows.

%prep
%setup -q -n Inkrail-Linux-%{archive_arch}

%build

%install
mkdir -p %{buildroot}/opt/inkrail
cp -a inkrail ui notices %{buildroot}/opt/inkrail/
install -Dm755 /dev/stdin %{buildroot}%{_bindir}/inkrail <<'SH'
#!/bin/sh
exec /opt/inkrail/inkrail "$@"
SH
install -Dm644 share/applications/inkrail.desktop %{buildroot}%{_datadir}/applications/inkrail.desktop
install -Dm644 share/icons/hicolor/512x512/apps/inkrail.png %{buildroot}%{_datadir}/icons/hicolor/512x512/apps/inkrail.png

%files
%license LICENSE.txt
%doc START-HERE.txt
/opt/inkrail
%{_bindir}/inkrail
%{_datadir}/applications/inkrail.desktop
%{_datadir}/icons/hicolor/512x512/apps/inkrail.png

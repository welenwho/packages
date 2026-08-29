#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-common.sh
source "$SCRIPT_DIR/ci-common.sh"
REPO_ROOT="$CI_REPO_ROOT"
# Keep the scanner/update pair reproducible.  Fetching from LuCI's moving
# master branch made a scheduled run able to change the extraction behavior
# without a corresponding change in this repository.
LUCI_I18N_COMMIT="${LUCI_I18N_COMMIT:-19365a7fd32bb223a3a347594496d35df2670154}"
LUCI_I18N_DIR="${LUCI_I18N_DIR:-}"
TEMP_DIR=""
SCANNER_DIR=""
POT_TEMP=""

cleanup() {
	[[ -z "$POT_TEMP" ]] || rm -f -- "$POT_TEMP"
	[[ -z "$TEMP_DIR" ]] || rm -rf -- "$TEMP_DIR"
	[[ -z "$SCANNER_DIR" ]] || rm -rf -- "$SCANNER_DIR"
}
trap cleanup EXIT INT TERM

if [[ -n "$LUCI_I18N_DIR" ]]; then
	SCAN_SCRIPT="$LUCI_I18N_DIR/i18n-scan.pl"
	UPDATE_SCRIPT="$LUCI_I18N_DIR/i18n-update.pl"
else
	TEMP_DIR="$(mktemp -d)"
	SCAN_SCRIPT="$TEMP_DIR/i18n-scan.pl"
	UPDATE_SCRIPT="$TEMP_DIR/i18n-update.pl"
	curl -fsSL --retry 3 \
		-o "$SCAN_SCRIPT" \
		"https://raw.githubusercontent.com/openwrt/luci/$LUCI_I18N_COMMIT/build/i18n-scan.pl"
	curl -fsSL --retry 3 \
		-o "$UPDATE_SCRIPT" \
		"https://raw.githubusercontent.com/openwrt/luci/$LUCI_I18N_COMMIT/build/i18n-update.pl"
fi

[[ -f "$SCAN_SCRIPT" ]] || {
	echo "Missing official i18n-scan.pl: $SCAN_SCRIPT" >&2
	exit 1
}
[[ -f "$UPDATE_SCRIPT" ]] || {
	echo "Missing official i18n-update.pl: $UPDATE_SCRIPT" >&2
	exit 1
}

XGETTEXT_BIN="$(command -v xgettext || true)"
[[ -n "$XGETTEXT_BIN" ]] || {
	echo "gettext's xgettext command is required for translation scanning" >&2
	exit 1
}
SCANNER_DIR="$(mktemp -d)"
XGETTEXT_FAILURE_LOG="$SCANNER_DIR/xgettext.failures"
cat > "$SCANNER_DIR/xgettext" <<'EOF'
#!/usr/bin/env bash

set +e
"$XGETTEXT_REAL" "$@"
result=$?
if (( result != 0 )); then
	printf 'xgettext invocation failed (exit %d): %s\n' "$result" "$*" >> "$XGETTEXT_FAILURE_LOG"
fi
exit "$result"
EOF
chmod 0755 "$SCANNER_DIR/xgettext"

cd "$REPO_ROOT"

if (( $# > 0 )); then
	PACKAGE_DIRS=("$@")
else
	mapfile -t PACKAGE_DIRS < <(ci_discover_packages)
fi

for package_dir in "${PACKAGE_DIRS[@]}"; do
	package_dir="${package_dir%/}"
	[[ -f "$package_dir/Makefile" ]] || {
		echo "Package Makefile not found: $package_dir/Makefile" >&2
		exit 1
	}
	[[ -d "$package_dir/po" ]] || continue

	templates=()
	if [[ -d "$package_dir/po/templates" ]]; then
		mapfile -t templates < <(
			find "$package_dir/po/templates" -maxdepth 1 -type f -name '*.pot' -print |
				sort
		)
	fi
	case "${#templates[@]}" in
		0)
			package_name="$(sed -n 's/^PKG_NAME:=//p' "$package_dir/Makefile" | head -n1)"
			[[ -n "$package_name" ]] || {
				echo "PKG_NAME not found in $package_dir/Makefile" >&2
				exit 1
			}
			package_name="${package_name#luci-app-}"
			package_name="${package_name#luci-theme-}"
			template="$package_dir/po/templates/$package_name.pot"
			;;
		1)
			template="${templates[0]}"
			;;
		*)
			echo "Multiple translation templates found in $package_dir" >&2
			exit 1
			;;
	esac

	sources=()
	for relative_path in \
		htdocs \
		luasrc \
		root/etc/init.d \
		root/etc/uci-defaults \
		root/etc/sbproxy/scripts \
		root/usr/bin \
		root/usr/libexec \
		root/usr/share/luci \
		root/usr/share/rpcd; do
		[[ -d "$package_dir/$relative_path" ]] && sources+=("$package_dir/$relative_path")
	done

	[[ "${#sources[@]}" -gt 0 ]] || continue
	mkdir -p -- "$(dirname -- "$template")"
	previous_message_count=0
	if [[ -f "$template" ]]; then
		previous_message_count="$(grep -c '^msgid ' "$template" || true)"
	fi
	POT_TEMP="$(mktemp "${template}.tmp.XXXXXX")"
	: > "$XGETTEXT_FAILURE_LOG"
	PATH="$SCANNER_DIR:$PATH" \
		XGETTEXT_REAL="$XGETTEXT_BIN" \
		XGETTEXT_FAILURE_LOG="$XGETTEXT_FAILURE_LOG" \
		perl "$SCAN_SCRIPT" "${sources[@]}" > "$POT_TEMP"
	if [[ -s "$XGETTEXT_FAILURE_LOG" ]]; then
		echo "Translation scan encountered xgettext errors for $package_dir; refusing to update translations" >&2
		cat "$XGETTEXT_FAILURE_LOG" >&2
		exit 1
	fi
	[[ -s "$POT_TEMP" ]] || {
		echo "Translation scan produced an empty template for $package_dir" >&2
		exit 1
	}
	message_count="$(grep -c '^msgid ' "$POT_TEMP" || true)"
	# A partial xgettext scan must never be allowed to remove existing
	# translations.  The old 20% threshold let smaller but still destructive
	# drops (for example 816 -> 739 messages) pass through.
	if (( previous_message_count > 0 && message_count < previous_message_count )); then
		echo "Translation scan unexpectedly dropped from $previous_message_count to $message_count messages for $package_dir" >&2
		exit 1
	fi
	mv -f -- "$POT_TEMP" "$template"
	POT_TEMP=""

	perl "$UPDATE_SCRIPT" "$package_dir/po"
	find "$package_dir/po" -type f -name '*.po~' -delete
	while IFS= read -r -d '' po_file; do
		# msgmerge marks source entries missing from the newly generated POT as
		# obsolete.  Check translated obsolete entries before cleaning them;
		# otherwise a broken/incomplete scan silently deletes real translations.
		obsolete_translated_count="$(
			msgattrib --only-obsolete --translated "$po_file" |
				awk '/^#~ msgid / { count++ } END { print count + 0 }'
		)"
		if (( obsolete_translated_count > 0 )); then
			echo "Translation scan marked $obsolete_translated_count translated messages obsolete in $po_file; refusing to remove them" >&2
			exit 1
		fi
		msgattrib --no-obsolete -o "$po_file" "$po_file"
		msgfmt --check -o /dev/null "$po_file"
		fuzzy_count="$(
			msgattrib --only-fuzzy --no-obsolete "$po_file" |
				awk '/^#,.*fuzzy/ { count++ } END { print count + 0 }'
		)"
		if (( fuzzy_count > 0 )); then
			echo "Fuzzy translation found: $po_file" >&2
			exit 1
		fi
		untranslated_count="$(
			msgattrib --untranslated --no-obsolete "$po_file" |
				awk '/^msgstr ""$/ { count++ } END { print count + 0 }'
		)"
		if (( untranslated_count > 0 )); then
			echo "Untranslated message found: $po_file" >&2
			exit 1
		fi
	done < <(find "$package_dir/po" -type f -name '*.po' -print0)

	echo "Updated translations: $package_dir"
done

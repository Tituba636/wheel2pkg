#!/bin/bash
#
# Quick and dirty script to convert a common class of python wheel
# packages into something that will quickly build in IBS
#
# Written by okir@suse.de, 2020

WHEEL_PREFIX="python-wheel-"
BUILD_ROOT=/var/tmp/build-$USER

function usage {

	echo "$@" >&2
	echo "Usage: wheel2pkg [-h] pkg-name" >&2
	exit 1
}

set -- `getopt h "$@"`

while [ $# ]; do
	opt=$1; shift
	case $opt in
	--)	break;;
	-h)	usage "Help";;
	*)	usage "Unknown option $opt";;
	esac
done

if [ $# -ne 1 ]; then
	usage "Bad number of package names"
fi
pkg_name=$1

pip download --no-deps $pkg_name

set -- $(ls $pkg_name*whl)

if [ $# -ne 1 ]; then
	echo "Bad expansion of $pkg_name*whl" >&2
	exit 1
fi

wheelfile=$1
wheelbase=${wheelfile%.whl}

set -- ${wheelbase//-/ }

basename=$1
pkg_version=$2
compat_py=$3
compat_api=$4
compat_os=$5

if [ "$basename" != "$pkg_name" ]; then
	echo "Parsed package name $basename does not match $pkg_name" >&2
	exit 1
fi

pkg_archive=$wheelbase.tar.bz2
pkg_manifest="$wheelbase.files"
pkg_author=
pkg_author_email=
pkg_description=
pkg_summary="Automated package of $pkg_name wheel"
pkg_url=
pkg_license=
pkg_requires=

if [ ! -f "$pkg_archive" ]; then
	virtualenv --clear $BUILD_ROOT
	. $BUILD_ROOT/bin/activate
	(cd $BUILD_ROOT && find -type f) | sort > PRE

	pip --disable-pip-version-check install --no-deps $pkg_name
	deactivate

	(cd $BUILD_ROOT && find -type f) | sort > POST

	comm -13 PRE POST | grep -v '\.pyc$' > FILES
	rm -f PRE POST


	echo "Creating $pkg_archive"
	tar -C $BUILD_ROOT -T FILES --owner root --group root -cvjf $pkg_archive


	echo "Creating $pkg_manifest"
	cat FILES | sed 's:^\.\/:/usr/:' > $pkg_manifest
fi

tar xOjf $pkg_archive --wildcards */METADATA|grep '^[-A-Za-z]\+[[:space:]]*:' | {
	OFS=$IFS
	IFS=": "

	echo declare -a pkg_dep
	echo declare -a pkg_pyvers
	while read tag rest; do
		echo "$tag=$rest" >&2
		case ${tag,,} in
		author)
			echo "pkg_author=\"$rest\"";;
		author-email)
			echo "pkg_author_email=\"$rest\"";;
		home-page)
			echo "pkg_url=\"$rest\"";;
		summary)
			echo "pkg_summary=\"$rest\"";;
		license)
			# FIXME: Translate license names
			echo "pkg_license=\"$rest\"";;
		requires-dist)
			echo "pkg_dep+=\"${rest// /}\"";;
		classifier)
			case ${rest// /} in
			ProgrammingLanguage::Python::2)
				echo "pkg_pyvers+=\"python2\"";;
			ProgrammingLanguage::Python::3)
				echo "pkg_pyvers+=\"python3\"";;
			esac
			: ;;
		esac

		# We may want to do something useful with the classifier
	done
} >info
. ./info
rm -f info

if [ -z "$pkg_description" ]; then
	if [ -n "$pkg_summary" ]; then
		pkg_description="$pkg_summary"
	fi
	if [ -n "$pkg_author" ]; then
		pkg_description+="\nWritten by $pkg_author"
		if [ -n "$pkg_author_email" ]; then
			pkg_description+=" ($pkg_author_email)"
		fi
	fi

	if [ -z "$pkg_description" ]; then
		pkg_description="..."
	fi
fi

if [ -n "$pkg_dep" ]; then
	pkg_requires=""
	for dep in ${pkg_dep}; do
		pkg_requires+="Requires:               $WHEEL_PREFIX${dep//[()]/ }\n"
	done
fi

pkg_suse_name="$WHEEL_PREFIX$pkg_name"
pkg_dir="$pkg_suse_name"

echo "Supporting versions ${pkg_pyvers}"

echo "Building package directory $pkg_dir"
mkdir -p $pkg_dir
cp $pkg_archive $pkg_manifest $pkg_dir
touch $pkg_dir/$pkg_suse_name.changes
sed < specfile.tmpl > $pkg_suse_name/$pkg_suse_name.spec \
	    -e "s/@@PKG_NAME@@/$pkg_suse_name/"  \
	    -e "s/@@PKG_SHORT_NAME@@/$pkg_name/"  \
	    -e "s/@@PKG_LICENSE@@/$pkg_license/"  \
	    -e "s/@@PKG_DESCRIPTION@@/$pkg_description/"  \
	    -e "s|@@PKG_URL@@|$pkg_url|"  \
	    -e "s/@@PKG_SUMMARY@@/$pkg_summary/"  \
	    -e "s/@@PKG_REQUIRES@@/$pkg_requires/"  \
	    -e "s/@@PKG_ARCHIVE@@/$pkg_archive/"  \
	    -e "s/@@PKG_MANIFEST@@/$pkg_manifest/"  \
	    -e "s/@@PKG_VERSION@@/$pkg_version/" 

echo "Done."

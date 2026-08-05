#!/bin/sh

# Make Altivec Toolchain's private tools available to every login shell without
# modifying the profile.d package's /etc/profile file.
_altivec_bin=/var/altivec/bin

if [ -d "$_altivec_bin" ]; then
  case ":${PATH-}:" in
    *":${_altivec_bin}:"*) ;;
    *) PATH="${_altivec_bin}${PATH:+:${PATH}}" ;;
  esac
  export PATH
fi

unset _altivec_bin

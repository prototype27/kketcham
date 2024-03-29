# bash/zsh git prompt support
#
# Copyright (C) 2006,2007 Shawn O. Pearce <spearce@spearce.org>
# Distributed under the GNU General Public License, version 2.0.
#
# This script allows you to see the current branch in your prompt.
#
# To enable:
#
#    1) Copy this file to somewhere (e.g. ~/.git-prompt.sh).
#    2) Add the following line to your .bashrc/.zshrc:
#        source ~/.git-prompt.sh
#    3) Change your PS1 to also show the current branch:
#         Bash: PS1='[\u@\h \W$(__git_ps1 " (%s)")]\$ '
#         ZSH:  PS1='[%n@%m %c$(__git_ps1 " (%s)")]\$ '
#
# The argument to __git_ps1 will be displayed only if you are currently
# in a git repository.  The %s token will be the name of the current
# branch.
#
# In addition, if you set GIT_PS1_SHOWDIRTYSTATE to a nonempty value,
# unstaged (*) and staged (+) changes will be shown next to the branch
# name.  You can configure this per-repository with the
# bash.showDirtyState variable, which defaults to true once
# GIT_PS1_SHOWDIRTYSTATE is enabled.
#
# You can also see if currently something is stashed, by setting
# GIT_PS1_SHOWSTASHSTATE to a nonempty value. If something is stashed,
# then a '$' will be shown next to the branch name.
#
# If you would like to see if there're untracked files, then you can set
# GIT_PS1_SHOWUNTRACKEDFILES to a nonempty value. If there're untracked
# files, then a '%' will be shown next to the branch name.
#
# If you would like to see the difference between HEAD and its upstream,
# set GIT_PS1_SHOWUPSTREAM="auto".  A "<" indicates you are behind, ">"
# indicates you are ahead, "<>" indicates you have diverged and "="
# indicates that there is no difference. You can further control
# behaviour by setting GIT_PS1_SHOWUPSTREAM to a space-separated list
# of values:
#
#     verbose       show number of commits ahead/behind (+/-) upstream
#     legacy        don't use the '--count' option available in recent
#                   versions of git-rev-list
#     git           always compare HEAD to @{upstream}
#     svn           always compare HEAD to your SVN upstream
#
# By default, __git_ps1 will compare HEAD to your SVN upstream if it can
# find one, or @{upstream} otherwise.  Once you have set
# GIT_PS1_SHOWUPSTREAM, you can override it on a per-repository basis by
# setting the bash.showUpstream config variable.

# __gitdir accepts 0 or 1 arguments (i.e., location)
# returns location of .git repo
__gitdir ()
{
	# Note: this function is duplicated in git-completion.bash
	# When updating it, make sure you update the other one to match.
	if [ -z "${1-}" ]; then
		if [ -n "${__git_dir-}" ]; then
			echo "$__git_dir"
		elif [ -n "${GIT_DIR-}" ]; then
			test -d "${GIT_DIR-}" || return 1
			echo "$GIT_DIR"
		elif [ -d .git ]; then
			echo .git
		else
			git rev-parse --git-dir 2>/dev/null
		fi
	elif [ -d "$1/.git" ]; then
		echo "$1/.git"
	else
		echo "$1"
	fi
}

# stores the divergence from upstream in $p
# used by GIT_PS1_SHOWUPSTREAM
__git_ps1_show_upstream ()
{
	local key value
	local svn_remote svn_url_pattern count n
	local upstream=git legacy="" verbose=""

	svn_remote=()
	# get some config options from git-config
	local output="$(git config -z --get-regexp '^(svn-remote\..*\.url|bash\.showupstream)$' 2>/dev/null | tr '\0\n' '\n ')"
	while read -r key value; do
		case "$key" in
		bash.showupstream)
			GIT_PS1_SHOWUPSTREAM="$value"
			if [[ -z "${GIT_PS1_SHOWUPSTREAM}" ]]; then
				p=""
				return
			fi
			;;
		svn-remote.*.url)
			svn_remote[ $((${#svn_remote[@]} + 1)) ]="$value"
			svn_url_pattern+="\\|$value"
			upstream=svn+git # default upstream is SVN if available, else git
			;;
		esac
	done <<< "$output"

	# parse configuration values
	for option in ${GIT_PS1_SHOWUPSTREAM}; do
		case "$option" in
		git|svn) upstream="$option" ;;
		verbose) verbose=1 ;;
		legacy)  legacy=1  ;;
		esac
	done

	# Find our upstream
	case "$upstream" in
	git)    upstream="@{upstream}" ;;
	svn*)
		# get the upstream from the "git-svn-id: ..." in a commit message
		# (git-svn uses essentially the same procedure internally)
		local svn_upstream=($(git log --first-parent -1 \
					--grep="^git-svn-id: \(${svn_url_pattern#??}\)" 2>/dev/null))
		if [[ 0 -ne ${#svn_upstream[@]} ]]; then
			svn_upstream=${svn_upstream[ ${#svn_upstream[@]} - 2 ]}
			svn_upstream=${svn_upstream%@*}
			local n_stop="${#svn_remote[@]}"
			for ((n=1; n <= n_stop; n++)); do
				svn_upstream=${svn_upstream#${svn_remote[$n]}}
			done

			if [[ -z "$svn_upstream" ]]; then
				# default branch name for checkouts with no layout:
				upstream=${GIT_SVN_ID:-git-svn}
			else
				upstream=${svn_upstream#/}
			fi
		elif [[ "svn+git" = "$upstream" ]]; then
			upstream="@{upstream}"
		fi
		;;
	esac

	# Find how many commits we are ahead/behind our upstream
	if [[ -z "$legacy" ]]; then
		count="$(git rev-list --count --left-right \
				"$upstream"...HEAD 2>/dev/null)"
	else
		# produce equivalent output to --count for older versions of git
		local commits
		if commits="$(git rev-list --left-right "$upstream"...HEAD 2>/dev/null)"
		then
			local commit behind=0 ahead=0
			for commit in $commits
			do
				case "$commit" in
				"<"*) ((behind++)) ;;
				*)    ((ahead++))  ;;
				esac
			done
			count="$behind	$ahead"
		else
			count=""
		fi
	fi

	# calculate the result
	if [[ -z "$verbose" ]]; then
		case "$count" in
		"") # no upstream
			p="" ;;
		"0	0") # equal to upstream
			p="$ZSH_THEME_GIT_PROMPT_EQUAL_REMOTE" ;;
		"0	"*) # ahead of upstream
			p="$ZSH_THEME_GIT_PROMPT_AHEAD_REMOTE" ;;
		*"	0") # behind upstream
			p="$ZSH_THEME_GIT_PROMPT_BEHIND_REMOTE" ;;
		*)	    # diverged from upstream
			p="$ZSH_THEME_GIT_PROMPT_DIVERGED_REMOTE" ;;
		esac
	else
		case "$count" in
		"") # no upstream
			p="" ;;
		"0	0") # equal to upstream
			p="$ZSH_THEME_GIT_PROMPT_VERBOSE_EQUAL_REMOTE" ;;
		"0	"*) # ahead of upstream
			p="$ZSH_THEME_GIT_PROMPT_VERBOSE_AHEAD_REMOTE${count#0	}" ;;
		*"	0") # behind upstream
			p="$ZSH_THEME_GIT_PROMPT_VERBOSE_BEHIND_REMOTE${count%	0}" ;;
		*)	    # diverged from upstream
			p="$ZSH_THEME_GIT_PROMPT_VERBOSE_DIVERGED_REMOTE_AHEAD${count#*	}$ZSH_THEME_GIT_PROMPT_VERBOSE_DIVERGED_REMOTE_BEHIND${count%	*}" ;;
		esac
	fi

}


# __git_ps1 accepts 0 or 1 arguments (i.e., format string)
# returns text to add to bash PS1 prompt (includes branch name)
__git_ps1 ()
{
	local g="$(__gitdir)"
	if [ -n "$g" ]; then
		local r=""
		local b=""
		if [ -f "$g/rebase-merge/interactive" ]; then
			r="|REBASE-i"
			b="$(cat "$g/rebase-merge/head-name")"
		elif [ -d "$g/rebase-merge" ]; then
			r="|REBASE-m"
			b="$(cat "$g/rebase-merge/head-name")"
		else
			if [ -d "$g/rebase-apply" ]; then
				if [ -f "$g/rebase-apply/rebasing" ]; then
					r="|REBASE"
				elif [ -f "$g/rebase-apply/applying" ]; then
					r="|AM"
				else
					r="|AM/REBASE"
				fi
			elif [ -f "$g/MERGE_HEAD" ]; then
				r="|MERGING"
			elif [ -f "$g/CHERRY_PICK_HEAD" ]; then
				r="|CHERRY-PICKING"
			elif [ -f "$g/BISECT_LOG" ]; then
				r="|BISECTING"
			fi

			b="$(git symbolic-ref HEAD 2>/dev/null)" || {

				b="$(
				case "${GIT_PS1_DESCRIBE_STYLE-}" in
				(contains)
					git describe --contains HEAD ;;
				(branch)
					git describe --contains --all HEAD ;;
				(describe)
					git describe HEAD ;;
				(* | default)
					git describe --tags --exact-match HEAD ;;
				esac 2>/dev/null)" ||

				b="$(cut -c1-7 "$g/HEAD" 2>/dev/null)..." ||
				b="unknown"
				b="($b)"
			}
		fi

		local w=""
		local i=""
		local s=""
		local u=""
		local c=""
		local p=""

		if [ "true" = "$(git rev-parse --is-inside-git-dir 2>/dev/null)" ]; then
			if [ "true" = "$(git rev-parse --is-bare-repository 2>/dev/null)" ]; then
				c="BARE:"
			else
				b="GIT_DIR!"
			fi
		elif [ "true" = "$(git rev-parse --is-inside-work-tree 2>/dev/null)" ]; then
			if [ -n "${GIT_PS1_SHOWDIRTYSTATE-}" ]; then
				if [ "$(git config --bool bash.showDirtyState)" != "false" ]; then
					git diff --no-ext-diff --quiet --exit-code || w=$ZSH_THEME_GIT_PROMPT_MODIFIED
					if git rev-parse --quiet --verify HEAD >/dev/null; then
						git diff-index --cached --quiet HEAD -- || i=$ZSH_THEME_GIT_PROMPT_ADDED
					else
						i="#"
					fi
				fi
			fi
			if [ -n "${ZSH_THEME_GIT_PROMPT_STASHED-}" ]; then
				git rev-parse --verify refs/stash >/dev/null 2>&1 && s=$ZSH_THEME_GIT_PROMPT_STASHED
			fi

			if [ -n "${ZSH_THEME_GIT_PROMPT_UNTRACKED-}" ]; then
				if [ -n "$(git ls-files --others --exclude-standard)" ]; then
					u=$ZSH_THEME_GIT_PROMPT_UNTRACKED
				fi
			fi

			if [ -n "${GIT_PS1_SHOWUPSTREAM-}" ]; then
				__git_ps1_show_upstream
			fi
		fi

		local f="$w$i$s$u"
		printf -- "${1:-%s}" "$(git_dirty_state)$(git_prompt_prefix)$c${b##refs/heads/}${f:+ $f}$(git_dirty_state)$r$p$(git_prompt_suffix)"
	fi
}

# Checks if working tree is dirty
function git_dirty_state() {
  local SUBMODULE_SYNTAX=''
  if [[ "$(git config --get oh-my-zsh.hide-status)" != "1" ]]; then
    if [[ $POST_1_7_2_GIT -gt 0 ]]; then
          SUBMODULE_SYNTAX="--ignore-submodules=dirty"
    fi
    if [[ -n $(git status -s ${SUBMODULE_SYNTAX}  2> /dev/null) ]]; then
      echo "$ZSH_THEME_GIT_PROMPT_DIRTY"
    else
      echo "$ZSH_THEME_GIT_PROMPT_CLEAN"
    fi
  fi
}

function prompt_char {
	if [ $UID -eq 0 ]; then echo "%{$fg_bold[red]%}#%{$reset_color%}"; else echo "%{$fg_bold[green]%}$%{$reset_color%}"; fi
}

function git_prompt_prefix() {
    echo "$ZSH_THEME_GIT_PROMPT_PREFIX"
}

function git_prompt_suffix() {
    echo "$(git_dirty_state)$ZSH_THEME_GIT_PROMPT_SUFFIX"
}

GIT_PS1_SHOWDIRTYSTATE="duh"
GIT_PS1_SHOWUPSTREAM="verbose"

ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg_bold[red]%}"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg_bold[green]%}"

ZSH_THEME_GIT_PROMPT_VERBOSE_EQUAL_REMOTE=" %{$fg_bold[green]%}u="
ZSH_THEME_GIT_PROMPT_VERBOSE_AHEAD_REMOTE=" %{$fg_bold[cyan]%}u+"
ZSH_THEME_GIT_PROMPT_VERBOSE_BEHIND_REMOTE=" %{$fg_bold[yellow]%}u-"
ZSH_THEME_GIT_PROMPT_VERBOSE_DIVERGED_REMOTE_AHEAD=" %{$fg_bold[cyan]%}u+"
ZSH_THEME_GIT_PROMPT_VERBOSE_DIVERGED_REMOTE_BEHIND=" %{$fg_bold[yellow]%}-"
ZSH_THEME_GIT_PROMPT_UNTRACKED="%{$fg_bold[yellow]%}%%"
ZSH_THEME_GIT_PROMPT_MODIFIED="%{$fg_bold[red]%}*"
ZSH_THEME_GIT_PROMPT_ADDED="%{$fg_bold[green]%}+"
ZSH_THEME_GIT_PROMPT_STASHED="%{$fg_bold[cyan]%}$"

ZSH_THEME_KKETCHAM_GIT_DIRTY_STATE=

ZSH_THEME_GIT_PROMPT_PREFIX=" ("
ZSH_THEME_GIT_PROMPT_SUFFIX=")%{$reset_color%}"

PROMPT='%(!.%{$fg_bold[red]%}.%{$fg_bold[green]%}%n@)%m:%{$fg_bold[cyan]%}%(!.%1~.%~)%{$reset_color%}$(__git_ps1)%_$(prompt_char)%{$reset_color%} '

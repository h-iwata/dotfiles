# Path to your oh-my-zsh configuration.
ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="afowler"

# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# Set to this to use case-sensitive completion
# CASE_SENSITIVE="true"

# Comment this out to disable bi-weekly auto-update checks
# DISABLE_AUTO_UPDATE="true"

# Uncomment to change how many often would you like to wait before auto-updates occur? (in days)
# export UPDATE_ZSH_DAYS=13

# Uncomment following line if you want to disable colors in ls
# DISABLE_LS_COLORS="true"

# Uncomment following line if you want to disable autosetting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment following line if you want red dots to be displayed while waiting for completion
# COMPLETION_WAITING_DOTS="true"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
plugins=(git ruby gem vundle)

source $ZSH/oh-my-zsh.sh

# Customize to your needs...
autoload -Uz colorsi
autoload -Uz compinit
compinit

precmd () {
  psvar=()
  export MANPAGER='less -R'
}

export LANGUAGE=ja_jp.UTF-8
export LANG=ja_JP.UTF-8
export LC_ALL=ja_JP.UTF-8


man(){
	env \
		LESS_TERMCAP_mb=$(printf "\e[1;31m") \
		LESS_TERMCAP_md=$(printf "\e[1;31m") \
		LESS_TERMCAP_me=$(printf "\e[0m") \
		LESS_TERMCAP_se=$(printf "\e[0m") \
		LESS_TERMCAP_so=$(printf "\e[1;44;33m") \
		LESS_TERMCAP_ue=$(printf "\e[0m") \
		LESS_TERMCAP_us=$(printf "\e[1;32m") \
		man "$@"
}

zstyle ':completion:*' ignore-parents parent pwd ..
zstyle ':completion:*:sudo:*' command-path /usr/local/sbin /usr/loal/bin /usr/sbin /usr/bin /sbin /bin
zstyle ':completion:*:processes' command 'ps x -o pid, s, args'

setopt print_eight_bit
setopt auto_menu
setopt hist_ignore_all_dups

bindkey '^R' history-incremental-pattern-search-backward

alias la='ls -a'
alias ll='ls -l'
alias cp='cp -i'
alias mv='mv -i'
alias mkdir='mkdir -p'
alias sudo='sudo '
alias df='df -h'

SPROMPT="%{$fg[yellow]%}%{$suggest%}(＠ﾟ□ ﾟ)ノ < %B%r%b %{$fg[yellow]%}かな? [yes(y), no(n),a,e]:${reset_color} "

stty -ixon -ixoff

export PATH=$PATH:~/.composer/vendor/bin
export PATH=/usr/local/bin:$PATH
export PATH=$HOME/Library/Android/sdk/platform-tools:$PATH

 # include .bashrc if it exists
if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi

if [ -f "$HOME/.bash_profile" ]; then
  . "$HOME/.bash_profile"
fi





# Add environment variable COCOS_CONSOLE_ROOT for cocos2d-x
export COCOS_CONSOLE_ROOT=/Users/h-iwata/Library/Cocos/CocosStore/cocos2d-x-3.8/tools/cocos2d-console/bin
export PATH=$COCOS_CONSOLE_ROOT:$PATH

# Add environment variable COCOS_TEMPLATES_ROOT for cocos2d-x
export COCOS_TEMPLATES_ROOT=/Users/h-iwata/Library/Cocos/CocosStore/cocos2d-x-3.8/templates
export PATH=$COCOS_TEMPLATES_ROOT:$PATH

# Add environment variable NDK_ROOT for cocos2d-x
export NDK_ROOT=/Users/h-iwata/Library/Android/ndk
export PATH=$NDK_ROOT:$PATH

# Add environment variable ANDROID_SDK_ROOT for cocos2d-x
export ANDROID_SDK_ROOT=/Users/h-iwata/Library/Android/sdk
export PATH=$ANDROID_SDK_ROOT:$PATH
export PATH=$ANDROID_SDK_ROOT/tools:$ANDROID_SDK_ROOT/platform-tools:$PATH

# Add RVM to PATH for scripting. Make sure this is the last PATH variable change.
export PATH="$PATH:$HOME/.rvm/bin"
export PATH="/usr/local/opt/mysql@8.0/bin:$PATH"

export ATOM_DEV_RESOURCE_PATH="$HOME/workspace/programming/javascript/atom"
eval $(brew shellenv)

# brew
export HOMEBREW_PREFIX="/usr/local";
export HOMEBREW_CELLAR="/usr/local/Cellar";
export HOMEBREW_REPOSITORY="/usr/local/Homebrew";
export PATH="/usr/local/bin:/usr/local/sbin${PATH+:$PATH}";
export MANPATH="/usr/local/share/man${MANPATH+:$MANPATH}:";
export INFOPATH="/usr/local/share/info:${INFOPATH:-}";
eval "$(pyenv init -)"

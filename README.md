for private use

INSTALL (MEMO)
----------------

`gem install homesick`

`cd ~`

`homesick clone h-iwata/dotfiles`

`git clone git://github.com/robbyrussell/oh-my-zsh.git .oh-my-zsh`

`homesick symlink dotfiles`

`source .zshrc`

`vundle`

### atom package list

*export*
apm list --installed --bare > .atom/packages.txt

*import*
apm install --packages-file .atom/packages.txt

for private use

INSTALL (MEMO)

`cd ~`

`git clone git://github.com/h-iwata/dotfiles`
`git clone git://github.com/gmarik/vundle.git dotfiles/vimfiles/bundle/vundle`
`git clone git://github.com/git://github.com/robbyrussell/oh-my-zsh.git .oh-my-zsh`

`ln -s dotfiles/.vimrc .vimrc`
`ln -s dotfiles/vimfiles .vim`
`ln -s dotfiles/.zshrc .zshrc`

`vim`

`:BundleInstall`

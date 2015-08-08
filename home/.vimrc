set nocompatible
filetype off 

set number
set title
set mouse=a
set nocompatible
set hidden
set clipboard+=unnamed
set nowritebackup
set nobackup
set showmatch
set autoindent
set smartindent
set shiftwidth=2
set tabstop=2
set softtabstop=2
set smarttab
set expandtab
set foldlevel=100
set ruler
set showcmd

set t_Co=256
set background=dark

set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()

" --------------
" plugin bundles
" --------------

Plugin 'gmarik/Vundle.vim'
Plugin 'b4winckler/vim-objc'
Plugin 'jQuery'
Plugin 'pangloss/vim-javascript'
Plugin 'kchmck/vim-coffee-script'
Plugin 'leshill/vim-json'
Plugin 'xml.vim'
Plugin 'Distinguished'
Plugin 'scrooloose/nerdtree'
Plugin 'jistr/vim-nerdtree-tabs'

syntax on

call vundle#end()            
filetype plugin indent on

colorscheme distinguished

let NERDTreeShowHidden = 1 
let file_name = expand("%:p")

let nerdtree_tabs_open_on_console_startup=1

if has('vim_starting') && file_name == ""
  "autocmd VimEnter *  :NERDTreeTabsToggle
endif
map <F4> <plug>NERDTreeTabsToggle<CR>

inoremap <c-s> <Esc>:w<cr>
inoremap <c-q> <Esc>:q<cr>
nnoremap <c-s> <Esc>:w<cr>
nnoremap <c-q> <Esc>:q<cr>

autocmd BufNewFile,BufRead *.h set filetype=objc











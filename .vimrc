set nocompatible
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
set rtp+=~/.vim/bundle/vundle/

call vundle#rc()

Bundle 'gmarik/vundle'

" --------------
" plugin bundles
" --------------

Bundle 'jQuery'
Bundle 'pangloss/vim-javascript'
Bundle 'kchmck/vim-coffee-script'
Bundle 'leshill/vim-json'
Bundle 'xml.vim'

Bundle "Distinguished"
set background=dark
set t_Co=256
syntax enable

colorscheme distinguished
Bundle 'scrooloose/nerdtree'
let NERDTreeShowHidden = 1
let file_name = expand("%:p")
if has('vim_starting') && file_name == ""
	autocmd VimEnter * call ExecuteNERDTree()
endif
function! ExecuteNERDTree()
"b:nerdstatus = 1 : NERDTree 表示中
"b:nerdstatus = 2 : NERDTree 非表示中
if !exists('g:nerdstatus')
	execute 'NERDTree ./'
	let g:windowWidth = winwidth(winnr())
	let g:nerdtreebuf = bufnr('')
	let g:nerdstatus = 1

elseif g:nerdstatus == 1
	execute 'wincmd t'
	execute 'vertical resize' 0
	execute 'wincmd p'
	let g:nerdstatus = 2
	elseif g:nerdstatus == 2
	execute 'wincmd t'
	execute 'vertical resize' g:windowWidth
	let g:nerdstatus = 1
endif
endfunction
noremap <c-e> :<c-u>:call ExecuteNERDTree()<cr>
autocmd BufEnter * NERDTreeMirror

noremap <c-s> <Esc>:w<cr>

filetype plugin indent on













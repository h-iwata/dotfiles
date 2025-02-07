# lit_rails_tpl/server

Rails で書かれたWEB＆APIサーバです。

## Rubyセットアップ

### Ruby 2.4.1をインストール

```bash
$ gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
$ \curl -sSL https://get.rvm.io | bash
$ rvm install 2.4.1
$ rvm use 2.4.1 --default
```

rbenv を使ってもらっても大丈夫です。

### gem 管理ツールをインストール

```bash
$ gem i bundler
```

※ドキュメントが不要な場合は（`--no-document`）オプションを付けてください。

### gem のインストール

```bash
$ bundle install
```

## Frontend の準備

[frontend: README](https://github.com/lifeistech/rails_react_ts_tpl/blob/master/frontend/README.md) を参照してください。

## サーバの起動

```bash
foreman start
```

frontend表示：　http://localhost:8080/
rails表示：　http://localhost:3000/

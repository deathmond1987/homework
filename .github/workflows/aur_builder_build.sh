name: test script install

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]

jobs:

  aur_builder_image_build:

    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4           
    - name: build_aur_builder_image
      run: docker build . --file yay_builder.Dockerfile

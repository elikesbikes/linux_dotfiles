# Colormap
function colormap() {
  for i in {0..255}; do print -Pn "%K{$i}  %k%F{$i}${(l:3::0:)i}%f " ${${(M)$((i%6)):#3}:+$'\n'}; done
}

function dockerent() {
  sudo docker exec -it $1 /bin/bash
}

function dockerents() {
  sudo docker exec -it $1 /bin/sh
}

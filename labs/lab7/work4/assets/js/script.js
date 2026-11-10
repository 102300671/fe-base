(function () {
  var poem = document.getElementById('poem');
  var links = document.querySelectorAll('.sizes a');

  function setSize(size) {
    poem.className = 'poem size-' + size;
    links.forEach(function (link) {
      link.style.fontWeight = link.dataset.size === size ? 'bold' : 'normal';
    });
  }

  links.forEach(function (link) {
    link.addEventListener('click', function () {
      setSize(link.dataset.size);
    });
  });

  setSize('middle');
})();
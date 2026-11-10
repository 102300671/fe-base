(function () {
  var countries = ['China', 'Korea', 'Japan', 'Philippines', 'Vietnam', 'Singapore', 'Laos'];
  var order = ['Laos', 'China', 'Japan', 'Korea', 'Philippines', 'Singapore', 'Vietnam'];

  var sourceList = document.getElementById('listSource');
  var orderList = document.getElementById('listOrder');
  var button = document.getElementById('orderBtn');

  function render(list, names) {
    list.innerHTML = '';
    names.forEach(function (name) {
      var li = document.createElement('li');
      li.textContent = name;
      list.appendChild(li);
    });
  }

  render(sourceList, countries);

  button.addEventListener('click', function () {
    var sorted = countries.slice().sort(function (a, b) {
      return order.indexOf(a) - order.indexOf(b);
    });
    render(orderList, sorted);
  });
})();
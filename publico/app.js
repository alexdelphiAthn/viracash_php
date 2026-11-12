/* Mejoras opcionales: la aplicación funciona igual sin JavaScript. */
(function () {
  'use strict';

  /* Fecha y serie: al cambiar la fecha se recargan las series vigentes. */
  var formulario = document.querySelector('form[data-refrescar]');
  if (formulario) {
    var fecha = formulario.querySelector('input[name="fecha"]');
    var accion = formulario.querySelector('input[name="accion"]');
    if (fecha && accion) {
      fecha.addEventListener('change', function () {
        if (!fecha.checkValidity()) {
          fecha.reportValidity();
          return;
        }
        accion.value = 'refrescar';
        formulario.submit();
      });
    }
    var serie = formulario.querySelector('select[name="serie"]');
    var otraSerie = formulario.querySelector('input[name="otra_serie"]');
    if (serie && otraSerie) {
      serie.addEventListener('change', function () {
        if (serie.value !== '') {
          otraSerie.value = '';
        }
      });
      otraSerie.addEventListener('input', function () {
        if (otraSerie.value !== '') {
          serie.value = '';
        }
      });
    }
  }

  /* Evita envíos dobles al pulsar dos veces en el móvil. */
  var formularios = document.querySelectorAll('form');
  for (var i = 0; i < formularios.length; i++) {
    formularios[i].addEventListener('submit', function (evento) {
      var form = evento.target;
      if (form.getAttribute('data-enviado') === '1') {
        evento.preventDefault();
        return;
      }
      form.setAttribute('data-enviado', '1');
      setTimeout(function () { form.removeAttribute('data-enviado'); }, 4000);
    });
  }
})();

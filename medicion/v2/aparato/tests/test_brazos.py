from aparato.brazos import BRAZOS


def test_los_tres_brazos_con_su_ref_version_y_modo():
    assert {n: (b.ref, b.version, b.modo) for n, b in BRAZOS.items()} == {
        "v1-serie": ("f7ae28f", "2026-09-11+567c77a", "serie"),
        "v2-serie": ("v2.1.0", "2026-09-23+3b3d849", "serie"),
        "v2-olas": ("v2.1.0", "2026-09-23+3b3d849", "olas"),
    }


def test_el_nombre_del_brazo_es_su_clave():
    assert all(b.nombre == n for n, b in BRAZOS.items())

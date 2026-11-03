RDEPENDS:${PN}:remove = "${@'kernel-module-configfs kernel-module-libcomposite kernel-module-usb-f-acm' if d.getVar('LUCKFOX_KERNEL') == 'vendor' else ''}"
RDEPENDS:${PN}:append = "${@' kernel-base' if d.getVar('LUCKFOX_KERNEL') == 'vendor' else ''}"

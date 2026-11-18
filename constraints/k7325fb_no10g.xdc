# Added only when NETSEC_10G=0. The GTX pads stay in the top port list, but with the
# PCS/PMA removed they are not fabric pins. Leaving them as ordinary I/O fails bitgen
# (DRC NSTD-1 / UCIO-1 on sfp_txp/sfp_txn). Drop the IO buffers so nothing is bonded there.
set_property IO_BUFFER_TYPE none [get_ports {sfp_txp[*] sfp_txn[*] sfp_rxp[*] sfp_rxn[*] mgt_refclk_p mgt_refclk_n}]

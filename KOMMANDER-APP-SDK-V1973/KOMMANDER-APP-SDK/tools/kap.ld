ENTRY(kap_main)
SECTIONS {
  . = 0;
  .text : { *(.text .text.*) }
  . = ALIGN(16);
  .rodata : { *(.rodata .rodata.*) }
  . = ALIGN(16);
  .data : { *(.data .data.*) }
  . = ALIGN(16);
  .bss : { *(.bss .bss.*) *(COMMON) }
  .kapmem 0 (INFO) : { KEEP(*(.kapmem)) }     /* V1452: KAP_MEMORY(heap, extra), read by pack.py, not loaded */
  /DISCARD/ : { *(.MIPS.abiflags) *(.reginfo) *(.pdr) *(.comment) *(.gnu.attributes) *(.note*) }
}

/* Prints the sizes of perl's fixed structures for the build whose CORE directory it is compiled against.
 * Build and run with sizes.sh; the output is recorded in ../profile.md. */
#include <EXTERN.h>
#include <perl.h>
#include <stdio.h>

int main(void)
{
    printf("SV head %zu\n", sizeof(SV));
    printf("XPV %zu  XPVIV %zu  XPVNV %zu  XPVMG %zu  XPVLV %zu  XPVGV %zu  XPVCV %zu\n",
           sizeof(XPV), sizeof(XPVIV), sizeof(XPVNV), sizeof(XPVMG), sizeof(XPVLV), sizeof(XPVGV), sizeof(XPVCV));
    printf("XPVAV %zu  XPVHV %zu  HE %zu  HEK header %zu\n", sizeof(XPVAV), sizeof(XPVHV), sizeof(HE), sizeof(HEK));
    return 0;
}

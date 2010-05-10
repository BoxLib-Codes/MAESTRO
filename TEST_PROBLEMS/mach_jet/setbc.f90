! set the boundary conditions

module setbc_module

  use bl_types
  use bl_error_module
  use bc_module
  use bl_constants_module
  use inlet_bc_module

  implicit none

  private

  public :: setbc_1d, setbc_2d, setbc_3d

contains

  subroutine setbc_1d(s,lo,hi,ng,bc,icomp)

    integer        , intent(in   ) :: lo(:),hi(:),ng
    real(kind=dp_t), intent(inout) :: s(lo(1)-ng:)
    integer        , intent(in   ) :: bc(:,:)
    integer        , intent(in   ) :: icomp

  end subroutine setbc_1d

  subroutine setbc_2d(s,lo,hi,ng,bc,icomp)    

    integer        , intent(in   ) :: lo(:),hi(:),ng
    real(kind=dp_t), intent(inout) :: s(lo(1)-ng:,lo(2)-ng:)
    integer        , intent(in   ) :: bc(:,:)
    integer        , intent(in   ) :: icomp

    !     Local variables
    integer :: i

    if(ng == 0) return

    !-------------------------------------------------------------------------- 
    ! lower X                                                                  
    !--------------------------------------------------------------------------
    if (bc(1,1) .eq. INTERIOR) then
       ! nothing to do - these ghost cells are filled with either
       ! multifab_fill_boundary or multifab_fill_ghost_cells
    else if (bc(1,1) .eq. PERIODIC) then
       ! nothing to do - these ghost cells are filled with either
       ! multifab_fill_boundary or multifab_fill_ghost_cells
    else 
       call bl_error("setbc_2d: bc(1,1) not yet supported")
    end if

    !--------------------------------------------------------------------------
    ! upper X
    !--------------------------------------------------------------------------
    if (bc(1,2) .eq. INTERIOR) then
       ! nothing to do - these ghost cells are filled with either
       ! multifab_fill_boundary or multifab_fill_ghost_cells
    else if (bc(1,2) .eq. PERIODIC) then
       ! nothing to do - these ghost cells are filled with either
       ! multifab_fill_boundary or multifab_fill_ghost_cells
    else 
       call bl_error("setbc_2d: bc(1,2) not yet supported")
    end if

    !--------------------------------------------------------------------------
    ! lower Y
    !--------------------------------------------------------------------------
    if (bc(2,1) .eq. EXT_DIR) then
       ! xvel
       if (icomp .eq. 1) s(lo(1)-ng:hi(1)+ng,lo(2)-ng:lo(2)-1) = 0.d0
       ! yvel
       if (icomp .eq. 2) s(lo(1)-ng:hi(1)+ng,lo(2)-ng:lo(2)-1) = 1.d0
       ! rho
       if (icomp .eq. 3) s(lo(1)-ng:hi(1)+ng,lo(2)-ng:lo(2)-1) = INLET_RHO
       ! rhoh
       if (icomp .eq. 4) s(lo(1)-ng:hi(1)+ng,lo(2)-ng:lo(2)-1) = INLET_RHOH
       ! first species
       if (icomp .eq. 5) s(lo(1)-ng:hi(1)+ng,lo(2)-ng:lo(2)-1) = ONE-1.d-12
       ! second species   
       if (icomp .eq. 6) s(lo(1)-ng:hi(1)+ng,lo(2)-ng:lo(2)-1) = 1.d-12
       ! temperature
       if (icomp .eq. 7) s(lo(1)-ng:hi(1)+ng,lo(2)-ng:lo(2)-1) = INLET_TEMP
       ! tracer
       if (icomp .eq. 8) s(lo(1)-ng:hi(1)+ng,lo(2)-ng:lo(2)-1) = 0.d0


       ! NOTE: if you want an inhomogeneous dirichlet condition, you need to write it
       s(:,lo(2)-ng:lo(2)-1) = 0.d0
    else if (bc(2,1) .eq. INTERIOR) then
       ! nothing to do - these ghost cells are filled with either
       ! multifab_fill_boundary or multifab_fill_ghost_cells
    else
       call bl_error("setbc_2d: bc(2,1) not yet supported")
    end if

    !--------------------------------------------------------------------------
    ! upper Y
    !--------------------------------------------------------------------------
    if (bc(2,2) .eq. FOEXTRAP) then
       do i = lo(1)-ng,hi(1)+ng
          s(i,hi(2)+1:hi(2)+ng) = s(i,hi(2))
       end do
    else if (bc(2,2) .eq. HOEXTRAP) then
       do i = lo(1)-ng,hi(1)+ng
          s(i,hi(2)+1:hi(2)+ng) = &
               ( 15.d0 * s(i,hi(2)  ) &
                -10.d0 * s(i,hi(2)-1) &
                + 3.d0 * s(i,hi(2)-2) ) * EIGHTH
       end do
    else if (bc(2,2) .eq. INTERIOR) then
       ! nothing to do - these ghost cells are filled with either
       ! multifab_fill_boundary or multifab_fill_ghost_cells
    else 
       call bl_error("setbc_2d: bc(2,2) not yet supported")
    end if

  end subroutine setbc_2d

  subroutine setbc_3d(s,lo,hi,ng,bc,icomp)

    integer        , intent(in   ) :: lo(:),hi(:),ng
    real(kind=dp_t), intent(inout) :: s(lo(1)-ng:,lo(2)-ng:,lo(3)-ng:)
    integer        , intent(in   ) :: bc(:,:)
    integer        , intent(in   ) :: icomp

  end subroutine setbc_3d

end module setbc_module
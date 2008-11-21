module cell_to_edge_module

  use bl_types
  use bl_error_module

  implicit none
  
  private

  public :: cell_to_edge
  
contains
  
  subroutine cell_to_edge(s0_cell,s0_edge)

    use bl_constants_module
    use geometry, only: r_start_coord, r_end_coord, nr, numdisjointchunks, spherical, nlevs

    real(kind=dp_t), intent(in   ) :: s0_cell(:,0:)
    real(kind=dp_t), intent(inout) :: s0_edge(:,0:)
    
    real(kind=dp_t)                ::  s0min,s0max,tmp
    integer                        ::  n,r,i

    if (spherical .eq. 1) then
       call bl_error('calling cell_to_edge with spherical .eq. 1')
    end if

    do n=1,nlevs
       do i=1,numdisjointchunks(n)
          do r=r_start_coord(n,i),r_end_coord(n,i)+1
             
             if (r .eq. 0) then
                ! if we are at lower domain boundary
                s0_edge(n,r) = s0_cell(n,r)
             else if (r .eq. 1 .or. r .eq. r_start_coord(n,i)) then
                ! if we are at lower domain boundary+1 OR
                ! if we are at bottom of coarse-fine interface that is not a domain boundary
                s0_edge(n,r) = HALF*(s0_cell(n,r-1)+s0_cell(n,r))
             else if (r .eq. nr(n)) then
                ! if we are at upper domain boundary
                s0_edge(n,r) = s0_cell(n,r-1)
             else if (r .eq. nr(n)-1 .or. r .eq. r_end_coord(n,i)+1) then
                ! if we are at upper domain boundary-1 OR
                ! if we are at top of coarse-fine interface that is not a domain boundary
                s0_edge(n,r) = HALF*(s0_cell(n,r)+s0_cell(n,r-1))
             else
                ! fourth order
                tmp = 7.d0/12.d0 * (s0_cell(n,r  ) + s0_cell(n,r-1)) &
                     -1.d0/12.d0 * (s0_cell(n,r+1) + s0_cell(n,r-2))
                s0min      = min(s0_cell(n,r),s0_cell(n,r-1))
                s0max      = max(s0_cell(n,r),s0_cell(n,r-1))
                s0_edge(n,r) = min(max(tmp,s0min),s0max)
             end if
             
          end do
       end do
    end do

  end subroutine cell_to_edge
  
end module cell_to_edge_module

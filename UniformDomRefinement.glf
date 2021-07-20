#############################################################################
#
# (C) 2021 Cadence Design Systems, Inc. All rights reserved worldwide.
#
# This sample script is not supported by Cadence Design Systems, Inc.
# It is provided freely for demonstration purposes only.
# SEE THE WARRANTY DISCLAIMER AT THE BOTTOM OF THIS FILE.
#
#############################################################################

###############################################################################
# Uniformly refine unstructured domains
###############################################################################

package require PWI_Glyph 2
pw::Script loadTk

# Globals
set availDomNames [list]
set entList [list]
set entColors [list]
set entColorModes [list]
set entLineWidths [list]
set connList [list]
set connColors [list]
set connColorModes [list]
set connLineWidths [list]
set tempName ""
set origConns [list]

# Options
set opt(Method) edgeRefineDomain
set opt(Steps) 1
set opt(StepsMax) 10
set opt(Smooth) 0
set opt(DeleteOld) 0
set opt(Fate) CreateHere
set opt(MoveLayer) [pw::Display getCurrentLayer]

set color(Valid)    SystemWindow
set color(Invalid)  MistyRose

# Widget hierarchy
set w(LabelTitle)           .title
set w(FrameMain)            .main
set   w(FramePick)            $w(FrameMain).pick
set     w(FramePickButtons)     $w(FramePick).buttons
set       w(ButtonPick)           $w(FramePickButtons).bPick
set       w(ButtonClear)          $w(FramePickButtons).bClear
set     w(LabelPick)            $w(FramePick).label
set     w(ListPick)             $w(FramePick).lbPick
set     w(PickListScrollY)      $w(FramePick).scrollPick
set   w(FrameOpts)            $w(FrameMain).opts
set     w(FrameMethod)          $w(FrameOpts).method
set       w(RadioEdge)            $w(FrameMethod).rEdge
set       w(RadioCentroid)        $w(FrameMethod).rCentroid
set     w(FrameSteps)           $w(FrameOpts).steps
set       w(LabelSteps)           $w(FrameSteps).label
set       w(EntrySteps)           $w(FrameSteps).numSteps
set     w(CheckSmooth)          $w(FrameOpts).cbSmooth
set     w(CheckDeleteOld)       $w(FrameOpts).cbDeleteOld
set     w(FrameFate)            $w(FrameOpts).fate
set       w(RadioHere)            $w(FrameFate).rHere
set       w(RadioMove)            $w(FrameFate).rMove
set w(FrameButtons)         .buttons
set   w(Logo)                 $w(FrameButtons).logo
set   w(ButtonOK)             $w(FrameButtons).bOk
set   w(ButtonApply)          $w(FrameButtons).bApply
set   w(ButtonCancel)         $w(FrameButtons).bCancel


# Open file in temporary location for saving refined mesh
proc getTempFileName {} {
  global tempName
  set tmpdir [pwd]
  if {[file exists "/tmp"]} {set tmpdir "/tmp"}
  catch {set tmpdir $::env(TMP)}
  catch {set tmpdir $::env(TEMP)}
  set tempName [file join $tmpdir "pw_temp.stl"]
}


# Write triangle cell to STL file
proc writeStlCell {pts i0 i1 i2 tempChannel} {
  set u [pwu::Vector3 subtract [lindex $pts $i1] [lindex $pts $i0]]
  set v [pwu::Vector3 subtract [lindex $pts $i2] [lindex $pts $i0]]
  set normal [pwu::Vector3 normalize [pwu::Vector3 cross $u $v]]  
  puts $tempChannel [format "facet normal %19.16e %19.16e %19.16e" \
    [pwu::Vector3 x $normal] \
    [pwu::Vector3 y $normal] \
    [pwu::Vector3 z $normal]]
  puts $tempChannel "  outer loop"
  puts $tempChannel [format "    vertex %19.16e %19.16e %19.16e" \
    [pwu::Vector3 x [lindex $pts $i0]] \
    [pwu::Vector3 y [lindex $pts $i0]] \
    [pwu::Vector3 z [lindex $pts $i0]]]
  puts $tempChannel [format "    vertex %19.16e %19.16e %19.16e" \
    [pwu::Vector3 x [lindex $pts $i1]] \
    [pwu::Vector3 y [lindex $pts $i1]] \
    [pwu::Vector3 z [lindex $pts $i1]]]
  puts $tempChannel [format "    vertex %19.16e %19.16e %19.16e" \
    [pwu::Vector3 x [lindex $pts $i2]] \
    [pwu::Vector3 y [lindex $pts $i2]] \
    [pwu::Vector3 z [lindex $pts $i2]]]
  puts $tempChannel "  endloop"
  puts $tempChannel "endfacet"
}


# Refine a domain by connecting each cell's centroid to its vertices
proc centroidRefineDomain {dom tempChannel} {
  puts $tempChannel "solid [$dom getName]"
  set cellCount [$dom getCellCount]
  set quadWarned false
  for {set c 1} {$c <= $cellCount} {incr c} {
    set cell [$dom getCell $c]
    # Get cell vertices and centroid
    set nln [llength $cell]
    set centroid [pwu::Vector3 zero]
    set pts [list]
    foreach node $cell {
      set pt [$dom getXYZ -grid $node]
      set centroid [pwu::Vector3 add $centroid $pt]
      lappend pts $pt
    }
    set centroid [pwu::Vector3 divide $centroid $nln]
    lappend pts $centroid

    # Generate new cells
    if {3 == $nln} {
      for {set i 0} {$i < $nln} {incr i} {
        # Compute new cell unit normal
        set i1 [expr ($i + 1) % $nln]
        writeStlCell $pts $i $i1 end $tempChannel
      }
    } elseif {!$warned} {
      puts "Currently, refining quads is unsupported"
      set quadWarned true
    }
  }
  puts $tempChannel "endsolid [$dom getName]"
}


# Refine a domain by splitting each cell's edges at their midpoints
proc edgeRefineDomain {dom tempChannel} {
  puts $tempChannel "solid [$dom getName]"
  set cellCount [$dom getCellCount]
  set quadWarned false
  for {set c 1} {$c <= $cellCount} {incr c} {
    set cell [$dom getCell $c]
    # Get cell vertices and midpoints
    set nln [llength $cell]
    set pts [list]
    foreach node $cell {
      lappend pts [$dom getXYZ -grid $node]
    }
    for {set i 0} {$i < $nln} {incr i} {
      set i1 [expr ($i + 1) % $nln]
      lappend pts [pwu::Vector3 scale \
        [pwu::Vector3 add [lindex $pts $i] [lindex $pts $i1]] 0.5]
    }

    # Generate new cells
    if {3 == $nln} {
      for {set i 0} {$i < $nln} {incr i} {
        set i1 [expr $i + 3]
        set i1_0 [expr $i1 % 3]
      }
      writeStlCell $pts 0 3 5 $tempChannel
      writeStlCell $pts 1 4 3 $tempChannel
      writeStlCell $pts 2 5 4 $tempChannel
      writeStlCell $pts 3 4 5 $tempChannel
    } elseif {!$warned} {
      puts "Currently, refining quads is unsupported"
      set quadWarned true
    }
  }
  puts $tempChannel "endsolid [$dom getName]"
}


# Refine domains and write refined domains to temp file
proc refineAndWrite {} {
  global opt entList tempName
  getTempFileName
  set tempChannel [open $tempName w]
  foreach ent $entList {
    if {[$ent isOfType pw::DomainUnstructured]} {
      $opt(Method) $ent $tempChannel
    } elseif {[$ent isOfType pw::BlockUnstructured]} {
      # Future Enhancement: refine blocks
      puts "Currently, refining blocks is unsupported"
    } else {
      puts "Unsupported entity chosen for refinement: [$ent getName]"
    }
  }
  close $tempChannel
}


# Define db entities associated with each domain
set dbProjEnts [list]
proc defineDBProjEnts {} {
  global entList dbProjEnts
  foreach ent $entList {
    lappend dbProjEnts [$ent getDatabaseEntities -solver]
  }
}


# Define connectors associated with each original domain
proc defineOriginalConnectors {} {
  global entList origConns
  set origConns [list]
  foreach ent $entList {
    set edgeCount [$ent getEdgeCount]
    set conns [list]
    for {set e 1} {$e <= $edgeCount} {incr e} {
      set edge [$ent getEdge $e]
      set connCount [$edge getConnectorCount]
      for {set c 1} {$c <= $connCount} {incr c} {
        lappend conns [$edge getConnector $c]
      }
    }
    set conns [lsort -unique $conns]
    lappend origConns $conns
  }
}


# Project domains (interior only) onto db surfaces
proc projectCurrentDomains {} {
  global entList dbProjEnts
  set idx 0
  set mod [pw::Application begin Modify $entList]
  foreach ent $entList {
    if {0 < [llength [lindex $dbProjEnts $idx]] } {
      set projEnts [list]
      foreach dbEnt [lindex $dbProjEnts $idx] {
        if {[$dbEnt isSurface] && [$dbEnt isBaseForProject]} {
          lappend projEnts $dbEnt
        }
      }
      puts "[$ent getName] : $projEnts"
      pw::GridEntity project -interior $ent $projEnts
      incr idx
    }
  }
  $mod end
}


# Match connectors on imported domains to correspond with connectors on
# original domains
proc matchOriginalConnectors {refStep} {
  global entList origConns opt

  set tol [pw::Grid getNodeTolerance]

  # Split new connectors at endpoints of original connectors
  set domCount [llength $entList]
  for {set d 0} {$d < $domCount} {incr d} {
    set ent [lindex $entList $d]
    set edgeCount [$ent getEdgeCount]
    for {set e 1} {$e <= $edgeCount} {incr e} {
      set edge [$ent getEdge $e]
      set connsToSplit [list]
      set connCount [$edge getConnectorCount]
      for {set c 1} {$c <= $connCount} {incr c} {
        lappend connsToSplit [$edge getConnector $c]
      }
      foreach con $connsToSplit {
        set splitLocs [list]
        foreach origCon [lindex $origConns $d] {
          $con closestPoint -parameter par0 -distance dist \
            [[$origCon getNode Begin] getPoint]
          if {$dist < $tol && $par0 > $tol && [expr 1.0 - $par0] > $tol} {
            lappend splitLocs $par0
          }
          $con closestPoint -parameter par1 -distance dist \
            [[$origCon getNode End] getPoint]
          if {$dist < $tol && $par1 > $tol && [expr 1.0 - $par1] > $tol} {
            lappend splitLocs $par1
          }
        }
        if [llength $splitLocs] {
          set splitLocs [lsort -unique $splitLocs]
          if {[catch {$con split $splitLocs}]} {
            puts "Warning: Could not split [$con getName]. ($splitLocs)"
            exit 1
          }
        }
      }
    }
  }

  # Join connectors at points that are not original endpoints
  for {set d 0} {$d < $domCount} {incr d} {
    set ent [lindex $entList $d]
    set edgeCount [$ent getEdgeCount]
    for {set e 1} {$e <= $edgeCount} {incr e} {
      set edge [$ent getEdge $e]
      for {set c 1; set connCount [$edge getConnectorCount]} \
            {$c <= $connCount && $connCount > 1} \
            {incr c; set connCount [$edge getConnectorCount]} {
        set con0 [$edge getConnector $c]
        set con1 [$edge getConnector [expr ($c % $connCount) + 1]]
        # Find shared node
        set n00 [$con0 getNode Begin]
        set n01 [$con0 getNode End]
        set n10 [$con1 getNode Begin]
        set n11 [$con1 getNode End]
        if {[$n00 equals $n10]} {
          set sharedNode $n00
        } elseif {[$n00 equals $n11]} {
          set sharedNode $n00
        } elseif {[$n01 equals $n10]} {
          set sharedNode $n01
        } elseif {[$n01 equals $n11]} {
          set sharedNode $n01
        }
        # Find a matching original endpoint
        set doJoin yes
        foreach origCon [lindex $origConns $d] {
          if {[[$origCon getNode Begin] equals $sharedNode]} {
            set doJoin no
            break
          }
          if {[[$origCon getNode End] equals $sharedNode]} {
            set doJoin no
            break
          }
        }
        if {$doJoin} {
          if {[catch {$con0 join $con1}]} {
            puts "Warning: Could not join [$con0 getName] and [$con1 getName]"
          }
        }
      }
    }
  }

  # Recreate definitions of new connectors to match old connectors on db curves
  set newConns [list]
  for {set d 0} {$d < $domCount} {incr d} {
    set origDomConns [lindex $origConns $d]
    set ent [lindex $entList $d]
    set edgeCount [$ent getEdgeCount]
    for {set e 1} {$e <= $edgeCount} {incr e} {
      set edge [$ent getEdge $e]
      set newConnCount [$edge getConnectorCount]
      for {set i 1} {$i <= $newConnCount} {incr i} {
        set newCon [$edge getConnector $i]
        if {-1 != [lsearch $newConns $newCon]} {
          continue
        }
        lappend newConns $newCon
        set modifyMode [pw::Application begin Modify [list $newCon]]
        set newBeg [$newCon getNode Begin]
        set newEnd [$newCon getNode End]
        # Find matching original connector
        set matchIdx -1
        set flipOrient false
        set minDist 1.0e10
        set origConnCount [llength $origDomConns]
        for {set c 0} {$c < $origConnCount} {incr c} {
          set origCon [lindex $origDomConns $c]
          set origBeg [$origCon getNode Begin]
          set origEnd [$origCon getNode End]
          if {[$newBeg equals $origBeg] && [$newEnd equals $origEnd]} {
            set newX1 [$newCon getXYZ -grid 3]
            set origX1 [$origCon getXYZ -grid 2]
            set dist [pwu::Vector3 length \
              [pwu::Vector3 subtract $newX1 $origX1]]
            if {$dist < $minDist} {
              set matchIdx $c
              set minDist $dist
              set flipOrient false
            }
          } elseif {[$newBeg equals $origEnd] && [$newEnd equals $origBeg]} {
            set newConDim [$newCon getDimension]
            set newX1 [$newCon getXYZ -grid [expr $newConDim - 2]]
            set origX1 [$origCon getXYZ -grid 2]
            set dist [pwu::Vector3 length \
              [pwu::Vector3 subtract $newX1 $origX1]]
            if {$dist < $minDist} {
              set matchIdx $c
              set minDist $dist
              set flipOrient true
            }
          }
        }
        if {-1 == $matchIdx} {
          puts "Warning: Could not find original match for [$newCon getName]"
          $modifyMode end
          continue
        }
        set origCon [lindex $origDomConns $matchIdx]
        set origDomConns [lreplace $origDomConns $matchIdx $matchIdx]
        if {$flipOrient} {
          $newCon setOrientation IMaximum
        }
        # Copy segment definitions
        set segs [list]
        set origSegCount [$origCon getSegmentCount]
        for {set s 1} {$s <= $origSegCount} {incr s} {
          lappend segs [$origCon getSegment -copy $s]
        }
        $newCon replaceAllSegments $segs
        $newCon setLayer $opt(MoveLayer)
        $modifyMode end
      }
    }
  }
}


# Refine all entities in entList
proc refineAll {} {
  global w opt entList tempName

  if {0 == [llength $entList ]} {
    return
  }

  defineDBProjEnts
  defineOriginalConnectors

  for {set refStep 1} {$refStep <= $opt(Steps)} {incr refStep} {
    refineAndWrite
    
    # Import grid from temp file
    set entList [pw::Grid import -type STL $tempName]
    
    # Fix imported grid
    matchOriginalConnectors $refStep
    projectCurrentDomains
    # Future Enhancement: Rename new doms and cons to correspond to originals
    # (something like *-refined-<level>)

    # Move refined entities to different layer
    if {$opt(Fate) == {CreateMove}} {
      foreach ent $entList {
        $ent setLayer $opt(MoveLayer)
      }
      if {$opt(MoveLayer) < [expr [pw::Layer getCount] -1]} {
        incr opt(MoveLayer)
      }
    }

    # Smooth refined entities
    if {$opt(Smooth)} {
      set solver [pw::Application begin UnstructuredSolver $entList]
      $solver run Smooth
      $solver end
    }

    pw::Display update
  }
}


# Select entities from Pointwise GUI
proc selectEntities {} {
  global w entList

  resetRenderAtts

  if {[pw::Grid getCount -type pw::DomainUnstructured] > 0} {
    wm withdraw .
    pw::Display selectEntities -description "Select entities for refinement."\
      -selectionmask [pw::Display createSelectionMask\
      -requireDomain Unstructured] \
      -preselect $entList \
      resultArray
    set entList $resultArray(Domains)
    $w(ListPick) selection clear 0 end
    foreach ent $entList {
      set entName [$ent getName]
      # Find name in listbox and mark that entry as selected
      for {set i 0} {$i < [$w(ListPick) size]} {incr i} {
        if {$entName == [$w(ListPick) get $i]} {
          $w(ListPick) selection set $i
        }
      }
    }
    if {[winfo exists .]} {
      wm deiconify .
    }
  } else {
    puts "Warning: No entities available for selection."
  }

  updateSelection
}


# Set the font for the title frame
proc setTitleFont { l } {
  global titleFont
  if { ! [info exists titleFont] } {
    set fontSize [font actual TkCaptionFont -size]
    set titleFont [font create -family [font actual TkCaptionFont -family] \
        -weight bold -size [expr {int(1.5 * $fontSize)}]]
  }
  $l configure -font $titleFont
}


# Update listbox with all available unstructured domains
proc updatePickList {} {
  global availDomNames
  set availDoms [pw::Grid getAll -type pw::DomainUnstructured]
  set availDomNames [list]
  foreach dom $availDoms {
    if {[pw::Display isLayerVisible [$dom getLayer]]} {
      lappend availDomNames [$dom getName]
    }
  }
}


# Reset gui entity coloring to original
proc resetRenderAtts {} {
  global entList entColors entColorModes entLineWidths \
    connList connColors connColorModes connLineWidths
  # Domains
  set entCount [llength $entList]
  for {set e 0} {$e < $entCount} {incr e} {
    set ent [lindex $entList $e]
    set fillMode [$ent getRenderAttribute FillMode]
    if {{Shaded} == $fillMode || {Flat} == $fillMode} {
      $ent setRenderAttribute SecondaryColor [lindex $entColors $e]
      $ent setRenderAttribute SecondaryColorMode [lindex $entColorModes $e]
    } else {
      $ent setColor [lindex $entColors $e]
      $ent setRenderAttribute ColorMode [lindex $entColorModes $e]
    }
    $ent setRenderAttribute LineWidth [lindex $entLineWidths $e]
  }
  set entColors [list]
  set entColorModes [list]
  set entLineWidths [list]
  # Connectors
  set connCount [llength $connList]
  for {set c 0} {$c < $connCount} {incr c} {
    set con [lindex $connList $c]
    $con setColor [lindex $connColors $c]
    $con setRenderAttribute ColorMode [lindex $connColorModes $c]
    $con setRenderAttribute LineWidth [lindex $connLineWidths $c]
  }
  set connColors [list]
  set connColorModes [list]
  set connLineWidths [list]
}


# Update list and gui with current selection
proc updateSelection {} {
  global w entList entColors entColorModes entLineWidths \
    connList connColors connColorModes connLineWidths

  set selection [$w(ListPick) curselection]
  set entList [list]
  set connList [list]
  foreach sel $selection {
    set name [$w(ListPick) get $sel]
    set ent [pw::GridEntity getByName $name]
    lappend entList $ent
    set fillMode [$ent getRenderAttribute FillMode]
    if {{Shaded} == $fillMode || {Flat} == $fillMode} {
      lappend entColors [$ent getRenderAttribute SecondaryColor]
      lappend entColorModes [$ent getRenderAttribute SecondaryColorMode]
      $ent setRenderAttribute SecondaryColor [list 1 1 1]
      $ent setRenderAttribute SecondaryColorMode Entity
    } else {
      lappend entColors [$ent getColor]
      lappend entColorModes [$ent getRenderAttribute ColorMode]
      $ent setColor [list 1 1 1]
      $ent setRenderAttribute ColorMode Entity
    }
    lappend entLineWidths [$ent getRenderAttribute LineWidth]
    $ent setRenderAttribute LineWidth 2
    # Get a list of all affected connectors
    set edgeCount [$ent getEdgeCount]
    for {set e 1} {$e <= $edgeCount} {incr e} {
      set edge [$ent getEdge $e]
      set connCount [$edge getConnectorCount]
      for {set c 1} {$c <= $connCount} {incr c} {
        lappend connList [$edge getConnector $c]
      }
    }
  }

  #Change connector rendering
  set connList [lsort -unique $connList]
  foreach con $connList {
    # Save original attributes
    lappend connColors [$con getColor]
    lappend connColorModes [$con getRenderAttribute ColorMode]
    lappend connLineWidths [$con getRenderAttribute LineWidth]
    # Set new attributes
    $con setColor [list 1.0 1.0 1.0]
    $con setRenderAttribute ColorMode Entity
    $con setRenderAttribute LineWidth 2
  }
}


# Enable/Disable action buttons based on current settings
proc updateButtons {} {
  global w color
  if {[string equal -nocase [$w(EntrySteps) cget -background] $color(Valid)]} {
    $w(ButtonOK) configure -state normal
    $w(ButtonApply) configure -state normal
  } else {
    $w(ButtonOK) configure -state disabled
    $w(ButtonApply) configure -state disabled
  }
  update
}


# Validate the entry for number of steps
proc validateSteps {steps widgetKey} {
  global w color opt
  if {[string is integer -strict $steps] && \
        $steps >= 0 && $steps < $opt(StepsMax)} {
    $w($widgetKey) configure -background $color(Valid)
  } else {
    $w($widgetKey) configure -background $color(Invalid)
  }
  updateButtons
  return 1
}


# Apply selection that was made before the script was executed
proc getPreSelection {} {
  global w entList
  if {[pw::Display getSelectedEntities \
        -selectionmask [pw::Display createSelectionMask\
        -requireDomain Unstructured] \
        resultArray]} {
    set entList $resultArray(Domains)
    $w(ListPick) selection clear 0 end
    foreach ent $entList {
      set entName [$ent getName]
      # Find name in listbox and mark that entry as selected
      for {set i 0} {$i < [$w(ListPick) size]} {incr i} {
        if {$entName == [$w(ListPick) get $i]} {
          $w(ListPick) selection set $i
        }
      }
    }
  }
  updateSelection
  pw::Display update
}


# Build user interface
proc makeWindow {} {
  global w opt availDomNames entList

  updatePickList

  wm title . "Uniformly Refine"
  label $w(LabelTitle) -text "Uniformly Refine Grid Entities"
  setTitleFont $w(LabelTitle)

  frame $w(FrameMain)

  frame $w(FramePick)
  frame $w(FramePickButtons)
  button $w(ButtonPick) -text "Select From GUI" -command {
    selectEntities
    pw::Display update
  }
  button $w(ButtonClear) -text "Clear Selection" -command {
    resetRenderAtts
    set entList [list]
    $w(ListPick) selection clear 0 end
  }
  label $w(LabelPick) -text "Selected Entities:"
  listbox $w(ListPick) -height 10 -selectmode extended \
    -listvariable availDomNames \
    -yscrollcommand {$w(PickListScrollY) set}
  scrollbar $w(PickListScrollY) -command {$w(ListPick) yview}


  labelframe $w(FrameOpts) -text "Options"
  frame $w(FrameMethod)
  radiobutton $w(RadioEdge) -text "Refine at edge midpoints" \
    -value edgeRefineDomain -variable opt(Method)
  radiobutton $w(RadioCentroid) -text "Refine at element centroids" \
    -value centroidRefineDomain -variable opt(Method)
  frame $w(FrameSteps)
  label $w(LabelSteps) -text "Number of refinement steps:"
  entry $w(EntrySteps) -width 5 -bd 2 -textvariable opt(Steps)
  $w(EntrySteps) configure -validate key -vcmd {validateSteps %P EntrySteps}
  checkbutton $w(CheckSmooth) -text "Smooth refined entities at each step" \
    -variable opt(Smooth)
  frame $w(FrameFate)
  checkbutton $w(CheckDeleteOld) -text "Delete original entities"\
    -variable opt(DeleteOld)
  radiobutton $w(RadioHere) \
    -text "Create refined entities in current layer" \
    -value CreateHere -variable opt(Fate) \
    -command {set opt(MoveLayer) [pw::Display getCurrentLayer]}
  radiobutton $w(RadioMove) \
    -text "Create refined entities in successive empty layers" \
    -value CreateMove -variable opt(Fate) \
    -command {
      for {set l [expr [pw::Layer getCount] - 1]} {$l >= 0} {incr l -1} {
        if {[llength [pw::Layer getLayerEntities $l]] > 0} {
          set opt(MoveLayer) [expr $l + 1]
          break
        }
      }
    }

  frame $w(FrameButtons)
  button $w(ButtonCancel) -text "Cancel" -command {resetRenderAtts; exit}
  button $w(ButtonApply) -text "Apply" -command {
    wm withdraw .
    resetRenderAtts
    refineAll
    pw::Display update
    if {[winfo exists .]} {
      wm deiconify .
    }
    updatePickList
    updateSelection
  }
  button $w(ButtonOK) -text "OK" -command {
    $w(ButtonApply) invoke
    $w(ButtonCancel) invoke
  }
  label $w(Logo) -image [cadenceLogo] -bd 0 -relief flat

  pack $w(LabelTitle) -side top
  # Spacer
  pack [frame .spMain -bd 1 -height 2 -relief sunken] -side top -fill x -pady 5

  pack $w(FrameMain) -side top -fill both

  pack $w(FramePick)
  grid $w(LabelPick) -sticky w
  grid $w(ListPick) $w(PickListScrollY) $w(FramePickButtons) -sticky ns
  pack $w(ButtonPick) -fill x -padx 10 -pady 3
  pack $w(ButtonClear) -fill x -padx 10 -pady 3
  
  pack $w(FrameOpts) -side top -ipadx 3 -ipady 3
  pack $w(FrameMethod) -side top -fill x
  pack $w(RadioEdge) -side top -anchor w
  pack $w(RadioCentroid) -side top -anchor w
  pack [frame $w(FrameOpts).spOpts1 -bd 1 -height 2 -relief sunken] -side top\
    -fill x -pady 3
  pack $w(FrameSteps) -side top -fill x
  pack $w(LabelSteps) -side left
  pack $w(EntrySteps) -side left
  pack $w(CheckSmooth) -side top -anchor w
  pack $w(CheckDeleteOld) -side top -anchor w
  pack [frame $w(FrameOpts).spOpts2 -bd 1 -height 2 -relief sunken] -side top\
    -fill x -pady 3
  pack $w(FrameFate) -side top -fill x
  pack $w(RadioHere) -side top -anchor w
  pack $w(RadioMove) -side left

  pack $w(FrameButtons) -side bottom -fill x -ipadx 5 -ipady 2
  pack $w(ButtonCancel) -side right -padx 3
  pack $w(ButtonApply) -side right -padx 3
  pack $w(ButtonOK) -side right -padx 3
  pack $w(Logo) -side left -padx 3

  bind . <Key-Return> {$w(ButtonApply) invoke}
  bind . <Control-Key-Return> {$w(ButtonOK) invoke}
  bind . <Key-Escape> {$w(ButtonCancel) invoke}
  bind $w(ButtonOK) <Key-Return> {
    $w(ButtonOK) flash
    $w(ButtonOK) invoke
  }
  bind $w(ButtonApply) <Key-Return> {
    $w(ButtonApply) flash
    $w(ButtonApply) invoke
  }
  bind $w(ButtonCancel) <Key-Return> {
    $w(ButtonCancel) flash
    $w(ButtonCancel) invoke
  }
  # Reflect listbox selection in GUI
  bind $w(ListPick) <ButtonRelease> {
    resetRenderAtts
    updateSelection
    pw::Display update
  }
  bind $w(ListPick) <B1-Motion> {
    resetRenderAtts
    updateSelection
    pw::Display update
  }

  wm resizable . 0 0
}


proc cadenceLogo {} {
  set logoData "
R0lGODlhgAAYAPQfAI6MjDEtLlFOT8jHx7e2tv39/RYSE/Pz8+Tj46qoqHl3d+vq62ZjY/n4+NT
T0+gXJ/BhbN3d3fzk5vrJzR4aG3Fubz88PVxZWp2cnIOBgiIeH769vtjX2MLBwSMfIP///yH5BA
EAAB8AIf8LeG1wIGRhdGF4bXD/P3hwYWNrZXQgYmVnaW49Iu+7vyIgaWQ9Ilc1TTBNcENlaGlIe
nJlU3pOVGN6a2M5ZCI/PiA8eDp4bXBtdGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1w
dGs9IkFkb2JlIFhNUCBDb3JlIDUuMC1jMDYxIDY0LjE0MDk0OSwgMjAxMC8xMi8wNy0xMDo1Nzo
wMSAgICAgICAgIj48cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudy5vcmcvMTk5OS8wMi
8yMi1yZGYtc3ludGF4LW5zIyI+IDxyZGY6RGVzY3JpcHRpb24gcmY6YWJvdXQ9IiIg/3htbG5zO
nhtcE1NPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvbW0vIiB4bWxuczpzdFJlZj0iaHR0
cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL3NUcGUvUmVzb3VyY2VSZWYjIiB4bWxuczp4bXA9Imh
0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8iIHhtcE1NOk9yaWdpbmFsRG9jdW1lbnRJRD0idX
VpZDoxMEJEMkEwOThFODExMUREQTBBQzhBN0JCMEIxNUM4NyB4bXBNTTpEb2N1bWVudElEPSJ4b
XAuZGlkOkIxQjg3MzdFOEI4MTFFQjhEMv81ODVDQTZCRURDQzZBIiB4bXBNTTpJbnN0YW5jZUlE
PSJ4bXAuaWQ6QjFCODczNkZFOEI4MTFFQjhEMjU4NUNBNkJFRENDNkEiIHhtcDpDcmVhdG9yVG9
vbD0iQWRvYmUgSWxsdXN0cmF0b3IgQ0MgMjMuMSAoTWFjaW50b3NoKSI+IDx4bXBNTTpEZXJpZW
RGcm9tIHN0UmVmOmluc3RhbmNlSUQ9InhtcC5paWQ6MGE1NjBhMzgtOTJiMi00MjdmLWE4ZmQtM
jQ0NjMzNmNjMWI0IiBzdFJlZjpkb2N1bWVudElEPSJ4bXAuZGlkOjBhNTYwYTM4LTkyYjItNDL/
N2YtYThkLTI0NDYzMzZjYzFiNCIvPiA8L3JkZjpEZXNjcmlwdGlvbj4gPC9yZGY6UkRGPiA8L3g
6eG1wbWV0YT4gPD94cGFja2V0IGVuZD0iciI/PgH//v38+/r5+Pf29fTz8vHw7+7t7Ovp6Ofm5e
Tj4uHg397d3Nva2djX1tXU09LR0M/OzczLysnIx8bFxMPCwcC/vr28u7q5uLe2tbSzsrGwr66tr
KuqqainpqWko6KhoJ+enZybmpmYl5aVlJOSkZCPjo2Mi4qJiIeGhYSDgoGAf359fHt6eXh3dnV0
c3JxcG9ubWxramloZ2ZlZGNiYWBfXl1cW1pZWFdWVlVUU1JRUE9OTUxLSklIR0ZFRENCQUA/Pj0
8Ozo5ODc2NTQzMjEwLy4tLCsqKSgnJiUkIyIhIB8eHRwbGhkYFxYVFBMSERAPDg0MCwoJCAcGBQ
QDAgEAACwAAAAAgAAYAAAF/uAnjmQpTk+qqpLpvnAsz3RdFgOQHPa5/q1a4UAs9I7IZCmCISQwx
wlkSqUGaRsDxbBQer+zhKPSIYCVWQ33zG4PMINc+5j1rOf4ZCHRwSDyNXV3gIQ0BYcmBQ0NRjBD
CwuMhgcIPB0Gdl0xigcNMoegoT2KkpsNB40yDQkWGhoUES57Fga1FAyajhm1Bk2Ygy4RF1seCjw
vAwYBy8wBxjOzHq8OMA4CWwEAqS4LAVoUWwMul7wUah7HsheYrxQBHpkwWeAGagGeLg717eDE6S
4HaPUzYMYFBi211FzYRuJAAAp2AggwIM5ElgwJElyzowAGAUwQL7iCB4wEgnoU/hRgIJnhxUlpA
SxY8ADRQMsXDSxAdHetYIlkNDMAqJngxS47GESZ6DSiwDUNHvDd0KkhQJcIEOMlGkbhJlAK/0a8
NLDhUDdX914A+AWAkaJEOg0U/ZCgXgCGHxbAS4lXxketJcbO/aCgZi4SC34dK9CKoouxFT8cBNz
Q3K2+I/RVxXfAnIE/JTDUBC1k1S/SJATl+ltSxEcKAlJV2ALFBOTMp8f9ihVjLYUKTa8Z6GBCAF
rMN8Y8zPrZYL2oIy5RHrHr1qlOsw0AePwrsj47HFysrYpcBFcF1w8Mk2ti7wUaDRgg1EISNXVwF
lKpdsEAIj9zNAFnW3e4gecCV7Ft/qKTNP0A2Et7AUIj3ysARLDBaC7MRkF+I+x3wzA08SLiTYER
KMJ3BoR3wzUUvLdJAFBtIWIttZEQIwMzfEXNB2PZJ0J1HIrgIQkFILjBkUgSwFuJdnj3i4pEIlg
eY+Bc0AGSRxLg4zsblkcYODiK0KNzUEk1JAkaCkjDbSc+maE5d20i3HY0zDbdh1vQyWNuJkjXnJ
C/HDbCQeTVwOYHKEJJwmR/wlBYi16KMMBOHTnClZpjmpAYUh0GGoyJMxya6KcBlieIj7IsqB0ji
5iwyyu8ZboigKCd2RRVAUTQyBAugToqXDVhwKpUIxzgyoaacILMc5jQEtkIHLCjwQUMkxhnx5I/
seMBta3cKSk7BghQAQMeqMmkY20amA+zHtDiEwl10dRiBcPoacJr0qjx7Ai+yTjQvk31aws92JZ
Q1070mGsSQsS1uYWiJeDrCkGy+CZvnjFEUME7VaFaQAcXCCDyyBYA3NQGIY8ssgU7vqAxjB4EwA
DEIyxggQAsjxDBzRagKtbGaBXclAMMvNNuBaiGAAA7"

  return [image create photo -format GIF -data $logoData]
}

makeWindow
getPreSelection
::tk::PlaceWindow . widget
tkwait window .

#############################################################################
#
# This file is licensed under the Cadence Public License Version 1.0 (the
# "License"), a copy of which is found in the included file named "LICENSE",
# and is distributed "AS IS." TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE
# LAW, CADENCE DISCLAIMS ALL WARRANTIES AND IN NO EVENT SHALL BE LIABLE TO
# ANY PARTY FOR ANY DAMAGES ARISING OUT OF OR RELATING TO USE OF THIS FILE.
# Please see the License for the full text of applicable terms.
#
#############################################################################

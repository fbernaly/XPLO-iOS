//
//  AVDepthData+CGImageSource.swift
//  XPLO
//
//  Created by Francisco Bernal Yescas on 1/9/18.
//  Copyright © 2018 Sean Fredrick, LLC. All rights reserved.
//

import Foundation
import AVFoundation

extension AVDepthData {
  
  convenience init?(fromSource source: CGImageSource) {
    guard let auxDataInfo = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0,
                                                                      kCGImageAuxiliaryDataTypeDisparity) as? [AnyHashable : Any] else {
                                                                        return nil
    }
    
    do {
      try self.init(fromDictionaryRepresentation: auxDataInfo)
    } catch {
      return nil
    }
  }
  
}

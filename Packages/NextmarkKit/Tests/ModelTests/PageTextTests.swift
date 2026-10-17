//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//


import Testing
@testable import Model

struct PageTextTests {
    @Test func skipLinksAndSignInPromptsAreLeftOut() {
        #expect(PageText.withoutFurniture("skip to main contentskip to footer\nApple MacBook Neo, 256GB") == "Apple MacBook Neo, 256GB")
        #expect(PageText.withoutFurniture("Skip to main content\nHi! Sign in or register\nHydroJug ease2o 32 oz") == "HydroJug ease2o 32 oz")
        #expect(PageText.withoutFurniture("Skip to\nMain content\nInsulated water bottle") == "Insulated water bottle")
        // What the page is about stays as it is.
        #expect(PageText.withoutFurniture("Sign in to see member prices on this coat") == "Sign in to see member prices on this coat")
    }
}
